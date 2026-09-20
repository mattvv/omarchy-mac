#!/usr/bin/env bash
"$HOME/.config/sketchybar/plugins-omarchy/popup_close.sh"

row() { # $1=item  $2=tz  $3=label
  local t
  t=$(TZ="$2" date '+%a %H:%M')
  sketchybar --set "$1" label="$(printf '%-9s %s' "$3" "$t")"
}

row clock.sj  "America/Puerto_Rico"  "San Juan"
row clock.nyc "America/New_York"     "New York"
row clock.sf  "America/Los_Angeles"  "SF"
row clock.bne "Australia/Brisbane"   "Brisbane"

sketchybar --set clock popup.drawing=toggle
