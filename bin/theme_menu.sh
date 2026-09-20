#!/usr/bin/env bash
# Omarchy SUPER+SHIFT+CTRL+SPACE equivalent: pick a theme.
# A native `choose from list` beats a 22-row sketchybar popup -- it is
# keyboard-navigable and type-to-filter.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$REPO" <<'PY'
import subprocess, sys, os
repo = sys.argv[1]
out = subprocess.run(["python3", repo + "/bin/theme.py", "list"],
                     capture_output=True, text=True).stdout
names, cur = [], ""
for line in out.splitlines():
    if not line.strip(): continue
    mark, name = line[0], line[1:].split()[0]
    names.append(name)
    if mark == "*": cur = name
lst = ", ".join('"%s"' % n for n in names)
script = (f'set t to {{{lst}}}\n'
          f'choose from list t with title "Omarchy theme" '
          f'with prompt "Current: {cur}" default items {{"{cur}"}}')
r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
choice = r.stdout.strip()
if choice and choice != "false":
    subprocess.run(["python3", repo + "/bin/theme.py", "set", choice])
PY
