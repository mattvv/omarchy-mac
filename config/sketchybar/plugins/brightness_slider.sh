#!/usr/bin/env bash
PLUG="$HOME/.config/sketchybar/plugins-omarchy"
if [ -n "$PERCENTAGE" ]; then
  python3 "$PLUG/brightness.py" set "$PERCENTAGE" >/dev/null 2>&1
  sketchybar --set display.bri slider.percentage="$PERCENTAGE"
fi
