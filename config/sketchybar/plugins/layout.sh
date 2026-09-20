#!/usr/bin/env bash
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
ACCENT=${ACCENT:-0xff798186}
MUTED=${MUTED:-0xff4b4e55}
AS=/opt/homebrew/bin/aerospace

CUR=$("$AS" list-windows --focused --format '%{window-layout}' </dev/null 2>/dev/null | head -1)
[ -n "$CUR" ] || CUR=$(cat "$HOME/.cache/omarchy-layout" 2>/dev/null)

case "$CUR" in
  scrolling)              sketchybar --set "$NAME" icon="󰓪" label="scrolling" icon.color=$ACCENT ;;
  tabs)                   sketchybar --set "$NAME" icon="󰓩" label="tabs"      icon.color=$ACCENT ;;
  h_accordion|v_accordion|accordion)
                          sketchybar --set "$NAME" icon="󰅪" label="accordion" icon.color=$MUTED ;;
  *)                      sketchybar --set "$NAME" icon="󰕰" label="dwindle"   icon.color=$MUTED ;;
esac
