#!/usr/bin/env bash
MUTE=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)
if [ "$MUTE" = "true" ]; then osascript -e "set volume without output muted"
else osascript -e "set volume with output muted"; fi
NAME=volume "$HOME/.config/sketchybar/plugins-omarchy/volume.sh"
