#!/usr/bin/env bash
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
if [ "$SENDER" = "mouse.exited.global" ] || [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" popup.drawing=off; exit 0
fi
sketchybar --set "$NAME" icon="󰏘" icon.color=${ACCENT:-0xff798186} \
    label="${THEME_NAME:-solitude}" label.color=${FG:-0xffcacccc}
