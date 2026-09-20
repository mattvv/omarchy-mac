#!/usr/bin/env bash
# Omarchy SUPER+L equivalent: dwindle (tiles) <-> scrolling (horizontal accordion)
# h_accordion keeps windows side by side so the adjacent one peeks in from the
# right, which is the closest AeroSpace gets to Hyprland's scrolling layout.
STATE="$HOME/.cache/omarchy-layout"
CUR=$(cat "$STATE" 2>/dev/null || echo tiles)
if [ "$CUR" = "tiles" ]; then
  NEW=accordion; CMD=h_accordion
else
  NEW=tiles;     CMD=tiles
fi
/opt/homebrew/bin/aerospace layout "$CMD" </dev/null >/dev/null 2>&1
echo "$NEW" > "$STATE"
sketchybar --trigger layout_change
