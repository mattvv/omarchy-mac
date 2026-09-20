#!/usr/bin/env bash
ACCENT=0xff798186
MUTED=0xff4b4e55
CUR=$(cat "$HOME/.cache/omarchy-layout" 2>/dev/null || echo tiles)
if [ "$CUR" = "accordion" ]; then
  sketchybar --set "$NAME" icon="󰓪" label="scrolling" icon.color=$ACCENT
else
  sketchybar --set "$NAME" icon="󰕰" label="dwindle" icon.color=$MUTED
fi
