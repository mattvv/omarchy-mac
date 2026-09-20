#!/usr/bin/env bash
"$HOME/.config/sketchybar/plugins-omarchy/popup_close.sh"
RAW=$(pmset -g batt)
SRC=$(echo "$RAW" | head -1 | sed "s/Now drawing from //; s/'//g")
REM=$(echo "$RAW" | grep -Eo '[0-9]+:[0-9]+ remaining' | head -1)
[ -z "$REM" ] && REM=$(echo "$RAW" | grep -o 'no estimate' | head -1)
[ -z "$REM" ] && REM="calculating…"
sketchybar --set battery.source label="$SRC"
sketchybar --set battery.time   label="$REM"
sketchybar --set battery popup.drawing=toggle
