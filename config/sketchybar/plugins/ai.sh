#!/usr/bin/env bash
if [ "$SENDER" = "mouse.exited.global" ] || [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" popup.drawing=off; exit 0
fi
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
PLUG="$HOME/.config/sketchybar/plugins-omarchy"
CL=$(python3 "$PLUG/ai_limits.py" 2>/dev/null)
CX=$(python3 "$PLUG/ai_limits_codex.py" 2>/dev/null)
read -r PCT COLOR <<<"$(python3 - "$CL" "$CX" <<'PY'
import sys,json
best=-1
for raw in sys.argv[1:3]:
    try: d=json.loads(raw)
    except Exception: continue
    if not d.get("ok"): continue
    for l in d.get("limits") or []:
        best=max(best,l["percent"])
if best<0: print("- 0xff4b4e55")
else:
    import os
    col=os.environ.get('WARN','0xffde6145') if best>=90 else (os.environ.get('ACCENT','0xff798186') if best>=70 else os.environ.get('ACCENT','0xff798186'))
    print(f"{best:.0f}% {col}")
PY
)"
sketchybar --set "$NAME" icon="󰚩" icon.color="${COLOR:-${ACCENT:-0xff798186}}" \
                         label="${PCT:-–}" label.color=${FG:-0xffcacccc}
