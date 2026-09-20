#!/usr/bin/env bash
"$HOME/.config/sketchybar/plugins-omarchy/popup_close.sh"
i=1
ps -Aceo pcpu,comm -r | sed -n '2,4p' | while read -r pct cmd; do
  sketchybar --set cpu.p$i label="$(printf '%-18.18s %5s%%' "$cmd" "$pct")"
  i=$((i+1))
done
sketchybar --set cpu popup.drawing=toggle
