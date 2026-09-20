#!/usr/bin/env bash

# Close this item's popup when the pointer leaves the bar.
if [ "$SENDER" = "mouse.exited.global" ] || [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi
ACCENT=0xff798186
MUTED=0xff4b4e55
VOL="${INFO:-$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)}"
MUTE=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)
case "$VOL" in ''|*[!0-9]*) VOL=0 ;; esac

if [ "$MUTE" = "true" ] || [ "$VOL" -eq 0 ]; then
  sketchybar --set "$NAME" icon="󰝟" icon.color=$MUTED label="${VOL}%"
else
  if   [ "$VOL" -gt 60 ]; then ICON="󰕾"
  elif [ "$VOL" -gt 20 ]; then ICON="󰖀"
  else                         ICON="󰕿"; fi
  sketchybar --set "$NAME" icon="$ICON" icon.color=$ACCENT label="${VOL}%"
fi
sketchybar --set volume.slider slider.percentage="$VOL" 2>/dev/null
