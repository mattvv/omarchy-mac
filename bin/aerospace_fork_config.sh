#!/usr/bin/env bash
# Re-apply the fork-only AeroSpace settings, if the fork is installed.
#
# ~/.aerospace.toml is generated from config/aerospace.toml, and that template
# cannot carry these keys: stock AeroSpace rejects an unknown key outright, so
# a shared template holding `scrolling-peek-width` would break every machine
# without the fork. They are appended afterwards instead.
#
# Which means every path that regenerates the config has to call this, or the
# peek and the scroll bindings silently vanish on the next install or
# `update.sh config aerospace` -- the config parses fine, the fork is still
# installed, and the feature is simply gone. Idempotent; safe to call always.
set -uo pipefail
CFG="$HOME/.aerospace.toml"
PEEK="${AEROSPACE_PEEK_WIDTH:-40}"
AS=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)

[ -f "$CFG" ] || exit 0
# `scroll` exists only in the fork, and `layout --help` does not enumerate
# layouts, so this is the reliable marker.
"$AS" --help </dev/null 2>&1 | grep -qE "^[[:space:]]+scroll[[:space:]]" || exit 0

python3 - "$CFG" "$PEEK" <<'PY'
import sys
cfg, peek = sys.argv[1], sys.argv[2]
s = open(cfg).read()
before = s
if "scrolling-peek-width" not in s:
    # Insert before the FIRST table header, not before a named one. A
    # top-level key written after any [table] or [[array]] belongs to that
    # table -- anchoring on [key-mapping] put it inside the
    # [[on-window-detected]] block that precedes it, and AeroSpace rejected
    # the whole config with "on-window-detected[0].scrolling-peek-width:
    # Unknown key".
    lines = s.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.lstrip().startswith("["):
            break
    else:
        i = len(lines)
    block = f"""# --- AeroSpace scrolling fork only ---
# Points of the NEXT page kept visible at the right edge in the scrolling
# layout. Auto-suppressed when a monitor sits to the right (a window manager
# cannot clip windows). Remove this if you revert to stock AeroSpace.
scrolling-peek-width = {peek}

"""
    s = "".join(lines[:i]) + block + "".join(lines[i:])
if "'scroll left'" not in s:
    s = s.replace("    # Modes", """    # Scrolling layout viewport (fork only). Arrows keep their directional
    # `focus` meaning; ctrl moves the viewport a page.
    alt-ctrl-left  = 'scroll left'
    alt-ctrl-right = 'scroll right'

    # Modes""", 1)
if s != before:
    open(cfg, "w").write(s)
    print("fork config applied")
else:
    print("fork config already present")
PY
