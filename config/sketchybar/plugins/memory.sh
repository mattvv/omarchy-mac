#!/usr/bin/env bash

# Close this item's popup when the pointer leaves the bar.
if [ "$SENDER" = "mouse.exited.global" ] || [ "$SENDER" = "mouse.exited" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi
TOTAL=$(sysctl -n hw.memsize)
PAGE=$(vm_stat | awk '/page size of/{print $8}')
[ -z "$PAGE" ] && PAGE=16384
FREE=$(vm_stat | awk '/Pages free/{gsub("\\.","",$3); print $3}')
INAC=$(vm_stat | awk '/Pages inactive/{gsub("\\.","",$3); print $3}')
SPEC=$(vm_stat | awk '/Pages speculative/{gsub("\\.","",$3); print $3}')
AVAIL=$(( (FREE + INAC + SPEC) * PAGE ))
USED=$(( TOTAL - AVAIL ))
PCT=$(( USED * 100 / TOTAL ))
sketchybar --set "$NAME" label="${PCT}%"
