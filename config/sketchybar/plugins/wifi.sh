#!/usr/bin/env bash
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null

# Close this item's popup when the pointer leaves the bar.
if [ "$SENDER" = "mouse.exited.global" ] || [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi
ACCENT=${ACCENT:-0xff798186}
MUTED=${MUTED:-0xff4b4e55}
DEV=$(networksetup -listallhardwareports 2>/dev/null \
      | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')
[ -z "$DEV" ] && DEV=en0

POWER=$(networksetup -getairportpower "$DEV" 2>/dev/null | grep -o "On\|Off")
# Is there an actual IP / association?
IP=$(ipconfig getifaddr "$DEV" 2>/dev/null)

if [ "$POWER" = "Off" ]; then
  sketchybar --set "$NAME" icon="󰤭" icon.color=$MUTED
elif [ -n "$IP" ]; then
  sketchybar --set "$NAME" icon="󰤨" icon.color=$ACCENT
else
  sketchybar --set "$NAME" icon="󰤯" icon.color=$MUTED
fi
