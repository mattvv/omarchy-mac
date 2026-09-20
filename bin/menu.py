#!/usr/bin/env python3
"""The Omarchy menu, macOS edition -- routing and dispatch.

Upstream keeps its menu in a JSONC file of dotted ids and lets a Quickshell
plugin render it. Quickshell is Linux-only, so the rendering is ours
(omarchy-picker --menu) and this is the part that knows what the menu *is*:

  menu.py rows [route]     TSV rows for the picker: id, icon, label, kind
  menu.py run <id>         run that entry's action
  menu.py resolve <name>   canonical id for an alias or a route
  menu.py tree             the whole menu, for looking at

Runs under /usr/bin/python3 (3.9), because that is what a GUI launch resolves
to -- see the PATH trap in CLAUDE.md.
"""
from __future__ import annotations
import os, subprocess, sys, json
from pathlib import Path

HOME = Path.home()
REPO = Path(__file__).resolve().parent.parent
BIN = HOME / ".local/bin"


def menu_file() -> Path:
    """Beside the repo when run from it, installed otherwise -- the same
    two-places problem that made theme.py return nothing silently."""
    for candidate in (REPO / "config/menu.jsonc",
                      HOME / ".local/share/omarchy-mac/menu.jsonc",
                      HOME / ".config/omarchy-mac/menu.jsonc"):
        if candidate.is_file():
            return candidate
    sys.exit("no menu.jsonc found")


def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments and trailing commas, without touching the
    insides of strings.

    A regex over whole lines is the obvious way and it is wrong: an action
    containing a URL (`open https://omarchy.org`) has a // in it, and a naive
    strip truncates the action to `open https:`. So walk the text instead and
    track whether we are inside a string or an escape."""
    out, i, n = [], 0, len(text)
    in_string = in_line_comment = in_block_comment = escaped = False
    while i < n:
        ch, nxt = text[i], text[i + 1] if i + 1 < n else ""
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                out.append(ch)
        elif in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 1
        elif in_string:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
            out.append(ch)
        elif ch == "/" and nxt == "/":
            in_line_comment = True
            i += 1
        elif ch == "/" and nxt == "*":
            in_block_comment = True
            i += 1
        else:
            out.append(ch)
        i += 1

    # Trailing commas, again only outside strings.
    cleaned, i = [], 0
    text = "".join(out)
    n, in_string, escaped = len(text), False, False
    while i < n:
        ch = text[i]
        if in_string:
            cleaned.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
            cleaned.append(ch)
        elif ch == ",":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] in "}]":
                pass                      # drop it
            else:
                cleaned.append(ch)
        else:
            cleaned.append(ch)
        i += 1
    return "".join(cleaned)


def load() -> dict:
    return json.loads(strip_jsonc(menu_file().read_text()))


def env() -> dict:
    """Actions are written against $OMARCHY_BIN so the file does not hardcode a
    home directory the way the sed-substituted configs do.

    PATH is set explicitly rather than inherited. Launched from the bar, a
    keybinding or Raycast, this process has no Homebrew on PATH, and an action
    as ordinary as `sketchybar --bar hidden=toggle` then fails with
    "command not found" -- into a pipe nobody reads, so the menu row simply
    appears to do nothing."""
    e = dict(os.environ)
    e["OMARCHY_BIN"] = str(BIN)
    e["OMARCHY_REPO"] = str(REPO)
    e["PATH"] = ":".join(["/opt/homebrew/bin", "/usr/local/bin", str(BIN),
                          "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
    # sketchybar-msg aborts outright without USER ("'env USER' not set!"), and
    # while launchd does set it for a GUI launch, backfilling costs nothing and
    # removes one way for an action to die silently.
    e.setdefault("USER", os.environ.get("LOGNAME") or Path.home().name)
    e.setdefault("HOME", str(HOME))
    return e


def children(entries: dict, route: str) -> list:
    """Direct children of a route. Root is depth 1."""
    out = []
    for key, value in entries.items():
        parts = key.split(".")
        if route in ("", "root"):
            if len(parts) == 1:
                out.append((key, value))
        elif key.startswith(route + ".") and len(parts) == len(route.split(".")) + 1:
            out.append((key, value))
    return out


def visible(value: dict) -> bool:
    cond = value.get("when")
    if not cond:
        return True
    return subprocess.run(["bash", "-c", cond], capture_output=True,
                          env=env(), stdin=subprocess.DEVNULL).returncode == 0


def checked(value: dict) -> bool:
    cond = value.get("checked")
    if not cond:
        return False
    return subprocess.run(["bash", "-c", cond], capture_output=True,
                          env=env(), stdin=subprocess.DEVNULL).returncode == 0


def rows(route: str = "root") -> str:
    entries = load()
    out = []
    for key, value in children(entries, route):
        if not visible(value):
            continue
        kind = "action" if "action" in value else "submenu"
        label = value.get("label", key.rsplit(".", 1)[-1])
        if checked(value):
            label += "  ✓"
        out.append("\t".join([key, value.get("icon", ""), label, kind,
                              " ".join(value.get("aliases", []))]))
    return "\n".join(out)


def resolve(name: str) -> str:
    entries = load()
    if name in entries:
        return name
    for key, value in entries.items():
        if name in value.get("aliases", []):
            return key
    return ""


def run(entry_id: str) -> int:
    entries = load()
    value = entries.get(entry_id)
    if value is None:
        sys.exit(f"unknown menu entry: {entry_id}")
    action = value.get("action")
    if not action:
        sys.exit(f"not an action: {entry_id}")
    # start_new_session: a menu entry frequently outlives the menu that ran it,
    # and the picker's wrapper is about to exit.
    return subprocess.Popen(["bash", "-c", action], env=env(),
                            stdin=subprocess.DEVNULL,
                            start_new_session=True).pid


def tree() -> str:
    entries = load()
    lines = []
    for key, value in entries.items():
        depth = len(key.split(".")) - 1
        kind = "action" if "action" in value else "submenu"
        lines.append(f'{"  " * depth}{value.get("icon", " ")} {value.get("label", key):<18} '
                     f'{kind:<8} {key}')
    return "\n".join(lines)


if __name__ == "__main__":
    argv = sys.argv[1:]
    cmd = argv[0] if argv else "tree"
    if cmd == "rows":
        print(rows(argv[1] if len(argv) > 1 else "root"))
    elif cmd == "run" and len(argv) > 1:
        run(argv[1])
    elif cmd == "resolve" and len(argv) > 1:
        print(resolve(argv[1]))
    elif cmd == "tree":
        print(tree())
    else:
        sys.exit(__doc__)
