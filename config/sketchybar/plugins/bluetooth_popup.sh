#!/usr/bin/env bash
"$HOME/.config/sketchybar/plugins-omarchy/popup_close.sh"
BU=/opt/homebrew/bin/blueutil

POWER=$("$BU" -p 2>/dev/null)
[ "$POWER" = "1" ] && STATE="On" || STATE="Off"
sketchybar --set bluetooth.status label="Bluetooth: $STATE"
sketchybar --set bluetooth.toggle label="Turn Bluetooth $([ "$STATE" = "On" ] && echo Off || echo On)"

# connected device names
names=$("$BU" --connected --format json 2>/dev/null \
        | sed 's/},{/}\n{/g' \
        | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')

i=1
while [ $i -le 3 ]; do
  n=$(echo "$names" | sed -n "${i}p")
  if [ -n "$n" ]; then
    sketchybar --set bluetooth.d$i label="  $n" drawing=on
  else
    if [ $i -eq 1 ]; then
      sketchybar --set bluetooth.d1 label="  no devices connected" drawing=on
    else
      sketchybar --set bluetooth.d$i label="" drawing=off
    fi
  fi
  i=$((i+1))
done

sketchybar --set bluetooth popup.drawing=toggle
