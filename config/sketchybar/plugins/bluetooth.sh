#!/usr/bin/env bash
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null

# Close this item's popup when the pointer leaves the bar.
if [ "$SENDER" = "mouse.exited.global" ] || [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

ACCENT=${ACCENT:-0xff798186}
MUTED=${MUTED:-0xff4b4e55}
BU=/opt/homebrew/bin/blueutil

POWER=$("$BU" -p 2>/dev/null)
NCONN=$("$BU" --connected --format json 2>/dev/null | grep -o '"address"' | wc -l | tr -d ' ')

if [ "$POWER" = "1" ]; then
  if [ "${NCONN:-0}" -gt 0 ]; then
    sketchybar --set "$NAME" icon="󰂱" icon.color=$ACCENT
  else
    sketchybar --set "$NAME" icon="󰂯" icon.color=$ACCENT
  fi
else
  sketchybar --set "$NAME" icon="󰂲" icon.color=$MUTED
fi
