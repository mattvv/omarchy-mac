#!/usr/bin/env python3
"""Omarchy theme switcher for macOS.

Mirrors omarchy's approach: never rewrite the app configs, generate one theme
file per app and have each config include it. Palettes are omarchy's own
themes/<name>/colors.toml, vendored under themes/.

  theme.py list                 names + mode
  theme.py current              active theme
  theme.py set <name>           generate, apply, restart services

  theme.py rows themes          TSV for omarchy-picker (value, image, label, palette)
  theme.py rows backgrounds [t] TSV of one theme's backgrounds

  theme.py bg current [theme]   the background in use for a theme
  theme.py bg set <path>        set and remember it for the current theme
  theme.py bg next              cycle (omarchy's SUPER+CTRL+SPACE does this too)
  theme.py fetch <name>|--all   download a theme's backgrounds from upstream
  theme.py raycast [dir]        (re)generate the Raycast script commands
"""
from __future__ import annotations
import json, os, re, shutil, subprocess, sys, time, urllib.request

try:
    import tomllib                # 3.11+
except ModuleNotFoundError:       # macOS still ships 3.9 as /usr/bin/python3,
    tomllib = None                # which is what a GUI launch often resolves to
from pathlib import Path

HOME = Path.home()
REPO = Path(__file__).resolve().parent.parent
STATE = HOME / ".local/state/omarchy-mac"


def _themes_dir() -> Path:
    """Run from the repo, palettes sit next to this file; installed into
    ~/.local/bin they live where install.sh copied them. Resolving only the
    first of those left the installed copy pointing at ~/.local/themes, which
    does not exist -- `list` and `set` then failed silently."""
    for candidate in (REPO / "themes", HOME / ".local/share/omarchy-mac/themes"):
        if candidate.is_dir():
            return candidate
    return REPO / "themes"


THEMES = _themes_dir()
# The upstream repo moved (basecamp/omarchy -> omacom/omarchy) and its default
# branch is no longer master, so the old raw.githubusercontent.com paths 404.
# The contents API is the stable way in: it redirects by repository id and
# hands back a download_url that is always current.
UPSTREAM_API = "https://api.github.com/repos/omacom/omarchy/contents/themes/{name}/backgrounds"

SB_THEME   = HOME / ".config/sketchybar/theme.sh"
GH_THEME   = HOME / ".config/ghostty/theme.conf"
WZ_THEME   = HOME / ".config/wezterm-theme.lua"
WALLPAPERS = HOME / "Pictures/omarchy-themes"
BG_STATE   = STATE / "backgrounds.json"

# What macOS will accept as a desktop picture. omarchy also lists video
# formats; System Events cannot set one, so they are left out.
IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".heic")


def parse_palette(text: str) -> dict:
    """The vendored palettes are flat `key = "value"` -- every line of all 22 of
    them. Reading those by hand costs nothing and drops a Python 3.11 floor that
    a script launched from Raycast, sketchybar or AeroSpace cannot count on."""
    if tomllib is not None:
        return tomllib.loads(text)
    out = {}
    for line in text.splitlines():
        m = re.match(r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"(.*)"\s*$', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def tool(name: str) -> str | None:
    """Homebrew is not on the default PATH, and a GUI launch does not inherit
    your shell's. Missing is survivable -- a theme still applies without the
    bar -- so callers skip rather than crash."""
    found = shutil.which(name)
    if found:
        return found
    for base in ("/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"):
        candidate = os.path.join(base, name)
        if os.path.exists(candidate):
            return candidate
    return None


def aerospace(*args: str) -> str:
    """Always with stdin closed: the CLI blocks on a non-TTY stdin and looks
    like a hang -- the single most expensive trap in this repo."""
    aero = tool("aerospace")
    if not aero:
        return ""
    r = subprocess.run([aero, *args], capture_output=True, text=True,
                       stdin=subprocess.DEVNULL)
    return r.stdout.strip()


def focused_workspace() -> str:
    return aerospace("list-workspaces", "--focused")


def keep_workspace(ws: str):
    """Stay where the user was.

    AeroSpace follows macOS focus, and applying a theme moves focus about --
    sketchybar reloads, borders restarts, the appearance flips. On a workspace
    with no windows of its own there is nothing here to focus, so macOS hands
    focus to an app on another workspace and AeroSpace goes along: you switch
    theme on an empty workspace 3 and land on 1.

    Detached, because the follow can arrive after we would have exited, and
    twice, because it can also arrive after we have already come back once."""
    if not (ws and tool("aerospace")):
        return
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "_keep-workspace", ws],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def osa(*script: str):
    binary = tool("osascript") or "/usr/bin/osascript"
    args = [binary]
    for line in script:
        args += ["-e", line]
    return subprocess.run(args, capture_output=True)


def hex6(v: str) -> str:
    return (v or "").strip().lstrip("#")[:6] or "000000"


def sb(v: str, alpha="ff") -> str:
    return f"0x{alpha}{hex6(v)}"


def load(name: str) -> dict:
    p = THEMES / f"{name}.toml"
    if not p.exists():
        sys.exit(f"unknown theme: {name}  (try: theme.py list)")
    return parse_palette(p.read_text())


def themes() -> list[tuple[str, str]]:
    out = []
    for p in sorted(THEMES.glob("*.toml")):
        try:
            out.append((p.stem, parse_palette(p.read_text()).get("mode", "dark")))
        except Exception:
            out.append((p.stem, "dark"))
    return out


def label(stem: str) -> str:
    """omarchy's labelForPath: dashes out, title case in."""
    return re.sub(r"[-_]+", " ", stem).title()


def border_pair(c: dict) -> tuple[str, str]:
    """omarchy stores the border as hyprland rgba() strings; borders(1) wants
    0xAARRGGBB, and a gradient when two colours are given."""
    raw = c.get("hyprland_active_border", "") or ""
    found = re.findall(r"rgba?\(([0-9a-fA-F]{6,8})\)", raw)
    if len(found) >= 2:
        a = f"gradient(top_left=0xff{found[0][:6]},bottom_right=0xff{found[1][:6]})"
    elif found:
        a = f"0xff{found[0][:6]}"
    else:
        a = sb(c.get("accent", "#798186"))
    inact = re.findall(r"rgba?\(([0-9a-fA-F]{6,8})\)", c.get("hyprland_inactive_border", "") or "")
    return a, (f"0xff{inact[0][:6]}" if inact else sb(c.get("muted", "#1e1e1e")))


def write_sketchybar(name, c):
    mode = c.get("mode", "dark")
    # On light themes the bar needs dark text on a light ground.
    SB_THEME.parent.mkdir(parents=True, exist_ok=True)
    act, inact = border_pair(c)
    SB_THEME.write_text(f'''#!/usr/bin/env bash
# Generated by theme.py -- do not edit. Active theme: {name} ({mode})
export THEME_NAME="{name}"
export THEME_MODE="{mode}"
export BG={sb(c.get("background"))}
export DARKBG={sb(c.get("dark_background", c.get("background")))}
export FG={sb(c.get("foreground"))}
export ACCENT={sb(c.get("accent"))}
export MUTED={sb(c.get("muted"))}
export SEL={sb(c.get("selection"))}
export WARN={sb(c.get("bright_red", c.get("red", "#de6145")))}
export BORDER_ACTIVE="{act}"
export BORDER_INACTIVE="{inact}"
''')
    SB_THEME.chmod(0o755)


def write_ghostty(name, c):
    GH_THEME.parent.mkdir(parents=True, exist_ok=True)
    pal = [c.get("dark_background"), c.get("red"), c.get("green"), c.get("yellow"),
           c.get("blue"), c.get("magenta"), c.get("cyan"), c.get("foreground"),
           c.get("muted"), c.get("bright_red"), c.get("bright_green"), c.get("bright_yellow"),
           c.get("bright_blue"), c.get("bright_magenta"), c.get("bright_cyan"),
           c.get("light_foreground", c.get("foreground"))]
    lines = [f"# Generated by theme.py -- do not edit. Active theme: {name}",
             f"background = {hex6(c.get('darker_background', c.get('background')))}",
             f"foreground = {hex6(c.get('foreground'))}",
             f"cursor-color = {hex6(c.get('accent'))}",
             f"cursor-text = {hex6(c.get('background'))}",
             f"selection-background = {hex6(c.get('selection'))}",
             f"selection-foreground = {hex6(c.get('foreground'))}"]
    lines += [f"palette = {i}=#{hex6(v)}" for i, v in enumerate(pal)]
    GH_THEME.write_text("\n".join(lines) + "\n")


def write_wezterm(name, c):
    def q(v): return f"'#{hex6(v)}'"
    ansi = [c.get("dark_background"), c.get("red"), c.get("green"), c.get("yellow"),
            c.get("blue"), c.get("magenta"), c.get("cyan"), c.get("foreground")]
    brights = [c.get("muted"), c.get("bright_red"), c.get("bright_green"), c.get("bright_yellow"),
               c.get("bright_blue"), c.get("bright_magenta"), c.get("bright_cyan"),
               c.get("light_foreground", c.get("foreground"))]
    WZ_THEME.write_text(f'''-- Generated by theme.py -- do not edit. Active theme: {name}
return {{
  foreground = {q(c.get("foreground"))},
  background = {q(c.get("darker_background", c.get("background")))},
  cursor_bg = {q(c.get("accent"))},
  cursor_border = {q(c.get("accent"))},
  cursor_fg = {q(c.get("background"))},
  selection_bg = {q(c.get("selection"))},
  selection_fg = {q(c.get("foreground"))},
  ansi = {{ {", ".join(q(v) for v in ansi)} }},
  brights = {{ {", ".join(q(v) for v in brights)} }},
}}
''')


# ── Backgrounds ──────────────────────────────────────────────────────────────
#
# One directory per theme under ~/Pictures/omarchy-themes, which is omarchy's
# ~/.local/state/omarchy/current/theme/backgrounds by another name. The chosen
# file per theme is remembered, so going back to a theme restores the wallpaper
# you left it on -- omarchy keeps a `current/background` symlink for this.

def bg_dir(name: str) -> Path:
    d = WALLPAPERS / name
    d.mkdir(parents=True, exist_ok=True)
    return d


def backgrounds(name: str) -> list[Path]:
    return sorted(p for p in bg_dir(name).iterdir()
                  if p.is_file() and p.suffix.lower() in IMAGE_EXT)


def fetch(name: str, first_only=False) -> list[Path]:
    """Download a theme's backgrounds. Silent on failure: a theme switch must
    still work on a plane."""
    d = bg_dir(name)
    have = backgrounds(name)
    # Unauthenticated GitHub allows 60 calls an hour per IP. The background
    # picker asks for a fetch on every open, which would spend that in an
    # afternoon -- once a day per theme is plenty for a gallery that changes
    # a few times a year.
    marker = d / ".fetched"
    if have and marker.exists() and time.time() - marker.stat().st_mtime < 86400:
        return have
    try:
        req = urllib.request.Request(UPSTREAM_API.format(name=name),
                                     headers={"Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=15) as r:
            items = json.loads(r.read())
    except Exception:
        return backgrounds(name)
    for item in items:
        if not isinstance(item, dict) or item.get("type") != "file":
            continue
        if not item["name"].lower().endswith(IMAGE_EXT):
            continue
        dest = d / item["name"]
        if not dest.exists():
            try:
                urllib.request.urlretrieve(item["download_url"], dest)
            except Exception:
                dest.unlink(missing_ok=True)
                continue
        if first_only:
            return backgrounds(name)   # leave the marker unset: more to come
    marker.touch()
    return backgrounds(name)


def bg_state() -> dict:
    try:
        return json.loads(BG_STATE.read_text())
    except Exception:
        return {}


def remember_bg(theme: str, path: Path):
    STATE.mkdir(parents=True, exist_ok=True)
    state = bg_state()
    state[theme] = str(path)
    BG_STATE.write_text(json.dumps(state, indent=2, sort_keys=True))


def current_bg(theme: str | None = None) -> Path | None:
    theme = theme or current()
    remembered = bg_state().get(theme)
    if remembered and Path(remembered).exists():
        return Path(remembered)
    have = backgrounds(theme)
    return have[0] if have else None


def set_desktop_picture(path: Path):
    # A path is data, not script: a quote or backslash in a filename would
    # otherwise end the AppleScript string early.
    quoted = str(path).replace("\\", "\\\\").replace('"', '\\"')
    osa('tell application "System Events" to set picture of '
        f'every desktop to "{quoted}"')


def set_bg(path: Path, theme: str | None = None):
    theme = theme or current()
    path = path.resolve()
    if not path.exists():
        sys.exit(f"no such background: {path}")
    remember_bg(theme, path)
    set_desktop_picture(path)


def next_bg():
    here = focused_workspace()
    theme = current()
    have = backgrounds(theme) or fetch(theme)
    if not have:
        sys.exit("no backgrounds for this theme")
    cur = current_bg(theme)
    i = have.index(cur) + 1 if cur in have else 0
    set_bg(have[i % len(have)], theme)
    keep_workspace(here)
    print(have[i % len(have)].name)


def wallpaper(name):
    """Apply this theme's wallpaper, fetching one if the cupboard is bare.

    Only the first image is fetched inline -- the rest arrive in a detached
    process so a theme switch never waits on the network for a picture you are
    not looking at yet."""
    have = backgrounds(name)
    if not have:
        have = fetch(name, first_only=True)
    chosen = current_bg(name)
    if chosen:
        set_bg(chosen, name)
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "fetch", name],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def set_appearance(mode: str):
    """Drive macOS light/dark to match the theme.

    This is what makes non-terminal apps follow -- browsers, Finder, native UI
    all key off the system appearance, not off our generated config files.
    """
    dark = "false" if mode == "light" else "true"
    osa("tell application \"System Events\" to tell appearance "
        f"preferences to set dark mode to {dark}")


def reload_terminals():
    """Terminals read their config at startup, so a theme swap leaves already
    open windows on the old palette.

    WezTerm watches its main config file but not files pulled in with dofile,
    so touch the main file to trigger its watcher. Ghostty has no reload CLI --
    `+new-window` is Linux-only -- but it binds reload_config to super+shift+,
    so drive that if it is running.
    """
    wz = Path.home() / ".wezterm.lua"
    if wz.exists():
        wz.touch()
    pgrep = tool("pgrep")
    if not (pgrep and subprocess.run([pgrep, "-x", "ghostty"],
                                     capture_output=True).returncode == 0):
        return
    # A keystroke goes wherever the keyboard already is, so sending one while
    # something else is focused either does nothing or -- worse -- brings
    # Ghostty forward and takes AeroSpace to its workspace. Only reload the
    # terminal you are actually looking at; the rest catch up when they restart.
    front = osa('tell application "System Events" to get name of first '
                'application process whose frontmost is true')
    if front.stdout.decode(errors="replace").strip().lower() != "ghostty":
        return
    osa('tell application "System Events" to tell process "Ghostty" '
        'to keystroke "," using {command down, shift down}')


def apply(name):
    here = focused_workspace()
    c = load(name)
    write_sketchybar(name, c); write_ghostty(name, c); write_wezterm(name, c)
    set_appearance(c.get("mode", "dark"))
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / "current-theme").write_text(name + "\n")
    wallpaper(name)

    act, inact = border_pair(c)
    pkill, borders_bin = tool("pkill"), tool("borders")
    if pkill and borders_bin:
        subprocess.run([pkill, "-x", "borders"], capture_output=True)
    # start_new_session: this often runs from a sketchybar click_script, and
    # the pkill below kills that script's parent. Without a new session the
    # replacement processes get torn down with it.
        subprocess.Popen([borders_bin, f"active_color={act}", f"inactive_color={inact}",
                          "width=4.0"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    # `--reload` re-executes sketchybarrc in place, which re-sources theme.sh.
    # Killing and respawning races sketchybar's lock file: the replacement
    # bails with "could not acquire lock-file" and the old, stale-themed
    # instance survives -- the bar then sits one theme behind.
    sketchybar = tool("sketchybar")
    if sketchybar:
        subprocess.run([sketchybar, "--reload"], capture_output=True)
    reload_terminals()
    keep_workspace(here)
    print(name)


def current() -> str:
    f = STATE / "current-theme"
    return f.read_text().strip() if f.exists() else "solitude"


# ── Picker rows ──────────────────────────────────────────────────────────────
#
# TSV consumed by omarchy-picker: value, preview image, label, palette. The
# palette is what lets a theme with no wallpaper downloaded yet still draw a
# card in its own colours instead of a hole.

PALETTE_KEYS = ["background", "dark_background", "foreground", "accent", "muted",
                "red", "green", "yellow", "blue", "magenta", "cyan"]


def palette(c: dict) -> str:
    return ",".join("#" + hex6(c.get(k, c.get("foreground", "#cacccc"))) for k in PALETTE_KEYS)


def rows_themes() -> str:
    lines = []
    for name, _mode in themes():
        c = load(name)
        bg = current_bg(name)
        lines.append("\t".join([name, str(bg) if bg else "", label(name), palette(c)]))
    return "\n".join(lines)


def rows_backgrounds(theme: str | None = None) -> str:
    theme = theme or current()
    have = backgrounds(theme) or fetch(theme)
    pal = palette(load(theme))
    return "\n".join("\t".join([str(p), str(p), label(p.stem), pal]) for p in have)


# ── Raycast ──────────────────────────────────────────────────────────────────
#
# Raycast is this setup's walker, so the theme and background switchers belong
# in it the same way omarchy puts them in `omarchy-menu`. Script commands are
# plain files in a directory Raycast is told to watch; the theme list has to be
# baked into the dropdown, which is why they are generated rather than shipped.

RAYCAST_DIR = HOME / ".local/share/omarchy-mac/raycast"

RAYCAST_HEADER = """#!/usr/bin/env bash
# Generated by theme.py -- do not edit.
# @raycast.schemaVersion 1
# @raycast.title %(title)s
# @raycast.mode silent
# @raycast.packageName Omarchy
# @raycast.icon %(icon)s
# @raycast.description %(description)s
%(argument)s"""


def write_raycast(dest: Path | None = None) -> Path:
    dest = dest or RAYCAST_DIR
    dest.mkdir(parents=True, exist_ok=True)
    bindir = HOME / ".local/bin"
    dropdown = json.dumps([{"title": label(n), "value": n} for n, _ in themes()])

    commands = {
        "omarchy-theme.sh": (
            {"title": "Omarchy Theme", "icon": "\U0001f3a8",
             "description": "Switch the Omarchy theme",
             "argument": '# @raycast.argument1 { "type": "dropdown", '
                         '"placeholder": "Theme", "data": ' + dropdown + ' }\n'},
            f'exec python3 "{bindir}/theme.py" set "$1"\n'),
        "omarchy-theme-picker.sh": (
            {"title": "Omarchy Theme Picker", "icon": "\U0001f5bc",
             "description": "Browse themes full screen", "argument": ""},
            # Detached: Raycast waits on a silent command, and this one owns the
            # screen until you pick something.
            f'("{bindir}/theme_menu.sh" >/dev/null 2>&1 &)\n'),
        "omarchy-background.sh": (
            {"title": "Omarchy Background", "icon": "\U0001f304",
             "description": "Pick a background for the current theme", "argument": ""},
            f'("{bindir}/bg_menu.sh" >/dev/null 2>&1 &)\n'),
        "omarchy-background-next.sh": (
            {"title": "Omarchy Next Background", "icon": "\u23ed",
             "description": "Cycle to the next background of the current theme",
             "argument": ""},
            f'exec python3 "{bindir}/theme.py" bg next\n'),
    }

    for name, (meta, body) in commands.items():
        f = dest / name
        f.write_text(RAYCAST_HEADER % meta + "\n" + body)
        f.chmod(0o755)
    return dest


if __name__ == "__main__":
    argv = sys.argv[1:]
    cmd = argv[0] if argv else "list"
    if cmd == "list":
        cur = current()
        for n, m in themes():
            print(f'{"*" if n == cur else " "} {n:<18} {m}')
    elif cmd == "current":
        print(current())
    elif cmd == "set" and len(argv) > 1:
        apply(argv[1])
    elif cmd == "rows":
        what = argv[1] if len(argv) > 1 else "themes"
        print(rows_themes() if what.startswith("theme")
              else rows_backgrounds(argv[2] if len(argv) > 2 else None))
    elif cmd == "bg":
        sub = argv[1] if len(argv) > 1 else "current"
        if sub == "set" and len(argv) > 2:
            set_bg(Path(argv[2]))
        elif sub == "next":
            next_bg()
        else:
            p = current_bg(argv[2] if len(argv) > 2 else None)
            print(p or "")
    elif cmd == "raycast":
        print(write_raycast(Path(argv[1]) if len(argv) > 1 else None))
    elif cmd == "_keep-workspace" and len(argv) > 1:
        # Detached helper, see keep_workspace().
        for delay in (0.0, 0.9):
            time.sleep(delay)
            if focused_workspace() not in ("", argv[1]):
                aerospace("workspace", argv[1])
    elif cmd == "fetch":
        names = [n for n, _ in themes()] if (len(argv) > 1 and argv[1] == "--all") \
            else argv[1:] or [current()]
        for n in names:
            got = fetch(n)
            print(f"{n:<18} {len(got)}")
    else:
        sys.exit(__doc__)
