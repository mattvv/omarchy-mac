#!/usr/bin/env bash
if [ "$SENDER" = "mouse.exited.global" ] || [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" popup.drawing=off; exit 0
fi
PLUG="$HOME/.config/sketchybar/plugins-omarchy"
LBL=$(python3 "$PLUG/display.py" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    c=next((m for m in d['modes'] if m['cur']), None)
    print(f\"{c['scale']:g}×\" if c and c.get('scale') else d.get('cur','—'))
except Exception: print('—')" 2>/dev/null)
sketchybar --set "$NAME" icon="󰍹" icon.color=0xff798186 label="${LBL:-—}" label.color=0xffcacccc
