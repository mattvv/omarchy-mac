#!/usr/bin/env bash

# Close this item's popup when the pointer leaves the bar.
if [ "$SENDER" = "mouse.exited.global" ] || [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi
# Omarchy shell.json clock format: "dddd HH:mm"
sketchybar --set "$NAME" label="$(date '+%A %H:%M')"
