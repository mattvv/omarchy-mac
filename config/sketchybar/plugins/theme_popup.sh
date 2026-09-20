#!/usr/bin/env bash
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
PLUG="$HOME/.config/sketchybar/plugins-omarchy"
"$PLUG/popup_close.sh"
python3 - <<'PY'
import os, subprocess, tomllib, glob
from pathlib import Path

THEMES = Path.home()/".local/share/omarchy-mac/themes"
cur_f  = Path.home()/".local/state/omarchy-mac/current-theme"
cur    = cur_f.read_text().strip() if cur_f.exists() else ""

def hx(v, a="ff"): return "0x"+a+(v or "").strip().lstrip("#")[:6]

rows=[]
for p in sorted(THEMES.glob("*.toml")):
    try: c = tomllib.loads(p.read_text())
    except Exception: continue
    rows.append((p.stem, c))

for i,(name,c) in enumerate(rows[:24], start=1):
    item=f"theme.r{i}"
    mark = "●" if name==cur else "○"
    subprocess.run(["sketchybar","--set",item,
        f"icon={mark}",
        f"icon.color={hx(c.get('accent'))}",
        f"label={name}",
        f"label.color={hx(c.get('foreground'))}",
        "background.drawing=on",
        f"background.color={hx(c.get('background'))}",
        "background.corner_radius=4",
        "background.height=22",
        "drawing=on",
        f"click_script=python3 $HOME/.local/bin/theme.py set {name}; sketchybar --set theme popup.drawing=off",
    ], capture_output=True)

for j in range(len(rows)+1, 25):
    subprocess.run(["sketchybar","--set",f"theme.r{j}","drawing=off","label=","click_script="],
                   capture_output=True)
PY
sketchybar --set theme popup.drawing=toggle
