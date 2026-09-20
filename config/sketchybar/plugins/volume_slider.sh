#!/usr/bin/env bash
if [ -n "$PERCENTAGE" ]; then
  osascript -e "set volume output volume $PERCENTAGE" 2>/dev/null
  osascript -e "set volume without output muted" 2>/dev/null
  sketchybar --set volume.slider slider.percentage="$PERCENTAGE"
  NAME=volume "$HOME/.config/sketchybar/plugins-omarchy/volume.sh"
fi
