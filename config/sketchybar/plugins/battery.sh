#!/usr/bin/env bash
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null

# Close this item's popup when the pointer leaves the bar.
if [ "$SENDER" = "mouse.exited.global" ] || [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi
FG=${FG:-0xffcacccc}
ACCENT=${ACCENT:-0xff798186}
WARN=${WARN:-0xffde6145}
PCT=$(pmset -g batt | grep -Eo '[0-9]+%' | tr -d '%' | head -1)
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ -z "$PCT" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

COLOR=$FG
if [ -n "$CHARGING" ]; then ICON="󰂄"; COLOR=$ACCENT
elif [ "$PCT" -ge 90 ]; then ICON="󰁹"
elif [ "$PCT" -ge 70 ]; then ICON="󰂀"
elif [ "$PCT" -ge 50 ]; then ICON="󰁾"
elif [ "$PCT" -ge 30 ]; then ICON="󰁼"
elif [ "$PCT" -ge 15 ]; then ICON="󰁻"; COLOR=$WARN
else ICON="󰁺"; COLOR=$WARN
fi

sketchybar --set "$NAME" drawing=on icon="$ICON" icon.color=$COLOR label="${PCT}%"
