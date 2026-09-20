#!/usr/bin/env bash
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
ACCENT=${ACCENT:-0xff798186}
MUTED=${MUTED:-0xff4b4e55}
CUR=$(cat "$HOME/.cache/omarchy-layout" 2>/dev/null || echo tiles)
if [ "$CUR" = "accordion" ]; then
  sketchybar --set "$NAME" icon="󰓪" label="scrolling" icon.color=$ACCENT
else
  sketchybar --set "$NAME" icon="󰕰" label="dwindle" icon.color=$MUTED
fi
