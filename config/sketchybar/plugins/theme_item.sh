#!/usr/bin/env bash
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
sketchybar --set "$NAME" icon="󰏘" icon.color=${ACCENT:-0xff798186} \
    label="${THEME_NAME:-solitude}" label.color=${FG:-0xffcacccc}
