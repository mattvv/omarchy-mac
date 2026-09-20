#!/usr/bin/env bash

# Close this item's popup when the pointer leaves the bar.
if [ "$SENDER" = "mouse.exited.global" ] || [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi
CPU=$(ps -A -o %cpu | awk '{s+=$1} END {printf "%.0f", s/'"$(sysctl -n hw.ncpu)"'}')
sketchybar --set "$NAME" label="${CPU}%"
