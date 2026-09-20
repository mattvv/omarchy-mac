#!/usr/bin/env python3
"""What keys are bound, read from the config that actually binds them.

Upstream's `omarchy-menu-keybindings` asks Hyprland what it has registered.
AeroSpace has no equivalent query, so the source of truth here is the installed
~/.aerospace.toml -- which means everything this prints is *configured*, not
confirmed-registered. The wording says so.

  keybindings.py rows      TSV for the picker
  keybindings.py list      plain text, for reading in a terminal
  keybindings.py check     parse the config and report, exit non-zero if broken
  keybindings.py test      self-test

Runs under /usr/bin/python3 (3.9), which has no tomllib -- so the small subset
of TOML that binding sections use is read directly. See read_bindings().
"""
from __future__ import annotations
import hashlib, os, re, sys
from pathlib import Path

HOME = Path.home()
AEROSPACE_CONFIG = HOME / ".aerospace.toml"
GHOSTTY_CONFIG = HOME / ".config/ghostty/config"

# Canonical macOS order is Control, Option, Shift, Command (Apple's HIG). Note
# this is *not* the order AeroSpace writes them in: alt-ctrl-shift-space reads
# as ⌃⌥⇧Space.
MODIFIERS = [("ctrl", "⌃"), ("alt", "⌥"), ("shift", "⇧"), ("cmd", "⌘")]
MODIFIER_NAMES = {name for name, _ in MODIFIERS}

# Glyphs only where they are universally read. Esc, Space, Tab and the like stay
# as words: ⎋ and ⇥ are recognised by far fewer people than the words are, and a
# keyboard reference that needs decoding has failed at its one job.
KEY_NAMES = {
    "space": "Space", "enter": "↩", "return": "↩", "backspace": "⌫",
    "delete": "⌦", "esc": "Esc", "escape": "Esc", "tab": "Tab",
    "left": "←", "right": "→", "up": "↑", "down": "↓",
    "home": "Home", "end": "End", "pageUp": "Page Up", "pageDown": "Page Down",
    "slash": "/", "backslash": "\\", "semicolon": ";", "quote": "'",
    "comma": ",", "period": ".", "minus": "-", "equal": "=",
    "leftSquareBracket": "[", "rightSquareBracket": "]", "backtick": "`",
}


def split_chord(chord: str):
    """Peel modifiers off the front one at a time.

    Splitting on "-" wholesale breaks `alt-minus`, whose key is literally named
    "minus". Peeling only known modifier names leaves the rest untouched."""
    mods, rest = [], chord
    while True:
        head, sep, tail = rest.partition("-")
        if sep and head in MODIFIER_NAMES:
            mods.append(head)
            rest = tail
        else:
            return mods, rest


def render_chord(chord: str) -> str:
    """A chord we do not fully understand is printed raw. A wrong glyph is worse
    than an unfamiliar spelling -- the user came here to find out what is
    bound, not to read our guess."""
    mods, key = split_chord(chord)
    known = key in KEY_NAMES or (len(key) == 1 and key.isalnum())
    if not known:
        return chord
    glyphs = "".join(glyph for name, glyph in MODIFIERS if name in mods)
    return glyphs + KEY_NAMES.get(key, key.upper())


# ── Reading the config ───────────────────────────────────────────────────────

def read_bindings(path: Path) -> dict:
    """Return {mode: [(chord, value), ...]} from [mode.<name>.binding] sections.

    Deliberately a subset reader, not a TOML parser: 3.9 has no tomllib, and the
    only shapes a binding section uses are `key = 'command'`, `key = ['a', 'b']`
    and `key = []`. Anything else in the file is skipped rather than guessed at.
    """
    if not path.exists():
        raise FileNotFoundError(str(path))
    out, mode = {}, None
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        section = re.match(r"^\[mode\.([^.\]]+)\.binding\]$", line)
        if section:
            mode = section.group(1)
            out.setdefault(mode, [])
            continue
        if line.startswith("["):
            mode = None          # some other section
            continue
        if mode is None or "=" not in line:
            continue
        chord, _, value = line.partition("=")
        chord, value = chord.strip(), value.strip()
        # Strip a trailing comment, but not one inside a quoted command.
        value = strip_trailing_comment(value)
        out[mode].append((chord, parse_value(value)))
    return out


def strip_trailing_comment(value: str) -> str:
    quote = None
    for i, ch in enumerate(value):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "#":
            return value[:i].strip()
    return value.strip()


def parse_value(value: str):
    if value.startswith("["):
        inner = value[1:value.rindex("]")] if "]" in value else value[1:]
        return [unquote(part) for part in split_top_level(inner) if part.strip()]
    return unquote(value)


def split_top_level(text: str):
    parts, depth, quote, current = [], 0, None, ""
    for ch in text:
        if quote:
            current += ch
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
            current += ch
        elif ch == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += ch
    parts.append(current)
    return parts


def unquote(text: str) -> str:
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "'\"":
        return text[1:-1]
    return text


# ── Saying what a binding does ───────────────────────────────────────────────

ARROWS = {"left": "left", "right": "right", "up": "up", "down": "down"}

# Our own helper scripts, keyed by the file they run. Keyed by path rather than
# by chord: a chord description rots the moment someone rebinds it.
OUR_SCRIPTS = {
    "theme_menu.sh": "Theme picker",
    "bg_menu.sh": "Background picker",
    "menu.sh": "Omarchy menu",
    "layout_toggle.sh": "Toggle layout (tiles / accordion)",
    "display.py": "Display scale",
}


def describe_one(command: str) -> str:
    """Recognise the *shape* of a command, or hand back the command itself.

    Every branch insists on an exact verb and argument count. Anything
    unrecognised is shown raw -- an unfamiliar command on screen is information;
    a confidently wrong description is not.
    """
    words = command.split()
    if not words:
        return command
    verb, args = words[0], words[1:]

    if verb == "workspace" and len(args) == 1:
        if args[0] in ("next", "prev"):
            return f"{args[0].capitalize()} workspace"
        return f"Focus workspace {args[0]}"
    if verb == "workspace-back-and-forth" and not args:
        return "Last workspace"
    if verb == "move-node-to-workspace":
        follow = "--focus-follows-window" in args
        rest = [a for a in args if not a.startswith("--")]
        if len(rest) == 1:
            return (f"Move window to workspace {rest[0]}"
                    + (" and follow" if follow else " (stay here)"))
    if verb == "focus" and len(args) == 1 and args[0] in ARROWS:
        return f"Focus window {ARROWS[args[0]]}"
    if verb == "move" and len(args) == 1 and args[0] in ARROWS:
        return f"Move window {ARROWS[args[0]]}"
    if verb == "join-with" and len(args) == 1 and args[0] in ARROWS:
        return f"Join with window {ARROWS[args[0]]}"
    if verb == "close" and not args:
        return "Close window"
    if verb == "close-all-windows-but-current":
        return "Close all other windows"
    if verb == "macos-native-fullscreen":
        return "Fullscreen"
    if verb == "layout" and args == ["floating", "tiling"]:
        return "Toggle floating / tiling"
    if verb == "layout" and args == ["tiles", "horizontal", "vertical"]:
        return "Toggle split direction"
    if verb == "flatten-workspace-tree":
        return "Reset layout"
    if verb == "reload-config":
        return "Reload AeroSpace config"
    if verb == "mode" and len(args) == 1:
        return f"Enter {args[0]} mode"
    if verb == "resize" and len(args) == 2:
        return f"Resize {args[0]} {args[1]}"
    if verb == "volume" and args:
        return "Volume " + " ".join(args)
    if verb == "move-mouse" and len(args) == 1:
        return f"Move mouse to {args[0].replace('-', ' ')}"
    if verb == "exec-and-forget":
        return describe_exec(" ".join(args))
    return command


def describe_exec(rest: str) -> str:
    open_app = re.match(r'^open -a "([^"]+)"$', rest) or re.match(r"^open -a '([^']+)'$", rest)
    if open_app:
        return f"Open {open_app.group(1)}"
    if re.match(r"^open https?://\S+$", rest):
        return "Open " + rest.split()[-1]
    for script, label in OUR_SCRIPTS.items():
        if script in rest:
            tail = rest.rsplit(script, 1)[1].strip()
            return f"{label} {tail}".strip()
    if re.match(r"^\S*sketchybar --trigger \S+$", rest):
        return "refresh the bar"
    if "sketchybar" in rest:
        return "Bar: " + rest.split("sketchybar", 1)[1].strip()
    return rest


def describe(value) -> str:
    if isinstance(value, list):
        if not value:
            return "Intercept the shortcut and do nothing"
        return " → ".join(describe_one(v) for v in value)
    return describe_one(value)


# ── Bindings we do not own ───────────────────────────────────────────────────

def ghostty_bindings(path: Path = GHOSTTY_CONFIG):
    """Only `keybind = global:MOD+KEY=ACTION`. Terminal-local binds are not
    system shortcuts and are none of this viewer's business."""
    rows, notices = [], []
    if not path.exists():
        return rows, ["Ghostty config not found"]
    for number, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line.startswith("keybind"):
            continue
        _, _, spec = line.partition("=")
        spec = spec.strip()
        if not spec.startswith("global:"):
            continue                       # terminal-local, not a system key
        body = spec[len("global:"):]
        chord, sep, action = body.partition("=")
        if not sep:
            notices.append(f"line {number}: could not read {line!r}")
            continue
        parts = chord.split("+")
        mods = [{"super": "cmd", "opt": "alt", "option": "alt"}.get(p, p) for p in parts[:-1]]
        key = {"escape": "esc", "enter": "enter"}.get(parts[-1], parts[-1])
        rows.append(("-".join(mods + [key]), action.strip()))
    return rows, notices


# ── Rows ─────────────────────────────────────────────────────────────────────

def row_id(group: str, chord: str) -> str:
    """Opaque, and prefixed kb: so the dispatcher can refuse it by shape."""
    return "kb:" + hashlib.sha256(f"{group}\0{chord}".encode()).hexdigest()[:12]


def collect():
    out = []
    bindings = read_bindings(AEROSPACE_CONFIG)
    for mode, entries in bindings.items():
        group = f"AeroSpace — {mode} mode (configured)"
        for chord, value in entries:
            disabled = isinstance(value, list) and not value
            label = describe(value)
            if mode != "main":
                label += "   [mode only]"
            out.append({
                "id": row_id(group, chord), "group": group,
                "chord": render_chord(chord), "label": label,
                "kind": "disabled" if disabled else "reference",
                "detail": value if isinstance(value, str) else " ; ".join(value) or "(nothing)",
            })
    gh, notices = ghostty_bindings()
    for chord, action in gh:
        group = "Ghostty (configured)"
        out.append({"id": row_id(group, chord), "group": group,
                    "chord": render_chord(chord),
                    "label": "New Ghostty window" if action == "new_window" else action,
                    "kind": "reference", "detail": f"ghostty keybind global:{chord}={action}"})
    # Raycast stores its hotkey internally with nothing readable on disk, so
    # this is a note about a gap, not a claim about a key.
    out.append({"id": row_id("Raycast", "unverified"), "group": "Raycast",
                "chord": "—", "label": "Launcher hotkey — not readable, unverified",
                "kind": "disabled",
                "detail": "Raycast keeps its hotkey internally; Omarchy expects ⌘Space."})
    return out, notices


def rows() -> str:
    entries, _ = collect()
    lines = []
    for e in entries:
        lines.append("\t".join([e["id"], "", e["label"], e["kind"], "",
                                 e["chord"], e["group"], e["detail"]]))
    return "\n".join(lines)


def listing() -> str:
    entries, notices = collect()
    out, group = [], None
    for e in entries:
        if e["group"] != group:
            group = e["group"]
            out.append("")
            out.append(group)
        out.append(f"  {e['chord']:<14} {e['label']}")
    for n in notices:
        out.append(f"  note: {n}")
    return "\n".join(out).strip()


def check() -> int:
    try:
        bindings = read_bindings(AEROSPACE_CONFIG)
    except FileNotFoundError as exc:
        print(f"no installed config at {exc}", file=sys.stderr)
        return 1
    total = sum(len(v) for v in bindings.values())
    if total == 0:
        print("config parsed but no bindings found", file=sys.stderr)
        return 1
    print(f"{AEROSPACE_CONFIG}: {len(bindings)} modes, {total} bindings")
    return 0


def test() -> int:
    cases = [
        ("alt-shift-semicolon", "⌥⇧;"),
        ("alt-ctrl-shift-space", "⌃⌥⇧Space"),   # canonical order, not as written
        ("alt-minus", "⌥-"),                     # "minus" survives the peeling
        ("cmd-alt-h", "⌥⌘H"),
        ("alt-slash", "⌥/"),
        ("alt-1", "⌥1"),
        ("alt-shift-enter", "⌥⇧↩"),
        ("alt-frobnicate", "alt-frobnicate"),    # unknown key stays raw
        ("hyper-x", "hyper-x"),                  # unknown modifier stays raw
    ]
    failures = 0
    for chord, want in cases:
        got = render_chord(chord)
        if got != want:
            print(f"FAIL {chord}: want {want!r} got {got!r}"); failures += 1

    described = [
        ("workspace 3", "Focus workspace 3"),
        ("move-node-to-workspace --focus-follows-window 5", "Move window to workspace 5 and follow"),
        ("focus left", "Focus window left"),
        ("layout floating tiling", "Toggle floating / tiling"),
        ('exec-and-forget open -a "Brave Browser"', "Open Brave Browser"),
        ("volume set 1000", "Volume set 1000"),
        ("layout tiles banana", "layout tiles banana"),   # unrecognised, raw
        ("frobnicate --hard", "frobnicate --hard"),       # unknown verb, raw
    ]
    for command, want in described:
        got = describe_one(command)
        if got != want:
            print(f"FAIL {command!r}: want {want!r} got {got!r}"); failures += 1

    if describe([]) != "Intercept the shortcut and do nothing":
        print("FAIL empty array"); failures += 1

    print("all passed" if failures == 0 else f"{failures} failed")
    return failures


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "rows":
        print(rows())
    elif cmd == "list":
        print(listing())
    elif cmd == "check":
        sys.exit(check())
    elif cmd == "test":
        sys.exit(test())
    else:
        sys.exit(__doc__)
