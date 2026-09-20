#!/usr/bin/env bash
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
PLUG="$HOME/.config/sketchybar/plugins-omarchy"
"$PLUG/popup_close.sh"
python3 - "$PLUG" <<'PY'
import sys, json, subprocess
plug = sys.argv[1]
d = json.loads(subprocess.run(["python3", plug+"/display.py"],
                              capture_output=True, text=True).stdout or "{}")
import os
HEAD = os.environ.get("MUTED",  "0xff4b4e55")
BODY = os.environ.get("FG",     "0xffcacccc")
ACC  = os.environ.get("ACCENT", "0xff798186")

rows = [("DISPLAYS", HEAD, None), ("  ● MacBook built-in", BODY, None),
        ("SCALE", HEAD, None)]
for m in reversed(d.get("modes", [])):        # most space first, like macOS
    mark = "●" if m["cur"] else " "
    txt  = f'  {mark} {m.get("scale",0):g}×   {m.get("name","")}'
    click = (f'python3 {plug}/display.py set {m["w"]}x{m["h"]}; '
             f'sketchybar --set display popup.drawing=off; '
             f'sleep 2; NAME=display {plug}/display.sh')
    rows.append((txt, ACC if m["cur"] else BODY, click))

items = [f"display.m{n}" for n in range(1, 13)]
for i, (txt, col, click) in enumerate(rows[:12]):
    subprocess.run(["sketchybar", "--set", items[i], f"label={txt}",
                    f"label.color={col}", "drawing=on",
                    f"click_script={click or ''}"], capture_output=True)
for j in range(len(rows), 12):
    subprocess.run(["sketchybar","--set",items[j],"label=","drawing=off",
                    "click_script="], capture_output=True)
PY
BRI=$(python3 "$PLUG/brightness.py" 2>/dev/null)
[ -n "$BRI" ] && sketchybar --set display.bri slider.percentage="$BRI"
sketchybar --set display popup.drawing=toggle
