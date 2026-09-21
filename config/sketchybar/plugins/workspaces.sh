#!/usr/bin/env bash
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
# Omarchy-style workspace list: only draw workspaces that hold a window, plus
# the focused one (so an empty workspace you just switched to is still visible).
# One aerospace round-trip, one sketchybar round-trip, for all 10 items.
FG=${FG:-0xffcacccc}
MUTED=${MUTED:-0xff4b4e55}
SEL=${SEL:-0xff343d41}
AEROSPACE=/opt/homebrew/bin/aerospace

focused="${FOCUSED_WORKSPACE:-$($AEROSPACE list-workspaces --focused </dev/null 2>/dev/null)}"
used=" $($AEROSPACE list-workspaces --monitor all --empty no </dev/null 2>/dev/null | tr '\n' ' ') "

args=()
for sid in $(seq 1 10); do
  if [ "$sid" = "$focused" ]; then
    args+=(--set space.$sid drawing=on \
      background.drawing=on background.color=$SEL \
      background.corner_radius=${ROUNDING:-0} background.height=24 \
      label.color=$FG)
  elif [[ $used == *" $sid "* ]]; then
    args+=(--set space.$sid drawing=on background.drawing=off label.color=$MUTED)
  else
    args+=(--set space.$sid drawing=off background.drawing=off)
  fi
done

sketchybar "${args[@]}"
