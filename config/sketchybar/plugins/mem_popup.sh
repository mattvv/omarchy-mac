#!/usr/bin/env bash
"$HOME/.config/sketchybar/plugins-omarchy/popup_close.sh"
i=1
ps -Aceo rss,comm -m | sed -n '2,4p' | while read -r rss cmd; do
  MB=$((rss/1024))
  sketchybar --set memory.p$i label="$(printf '%-18.18s %5sMB' "$cmd" "$MB")"
  i=$((i+1))
done
sketchybar --set memory popup.drawing=toggle
