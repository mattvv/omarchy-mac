#!/usr/bin/env bash
BU=/opt/homebrew/bin/blueutil
P=$("$BU" -p 2>/dev/null)
[ "$P" = "1" ] && "$BU" -p 0 || "$BU" -p 1
sleep 1
NAME=bluetooth "$HOME/.config/sketchybar/plugins-omarchy/bluetooth.sh"
sketchybar --set bluetooth popup.drawing=off
