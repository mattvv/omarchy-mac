#!/usr/bin/env bash
"$HOME/.config/sketchybar/plugins-omarchy/popup_close.sh"
DEV=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')
[ -z "$DEV" ] && DEV=en0
POWER=$(networksetup -getairportpower "$DEV" 2>/dev/null | grep -o "On\|Off")
IP=$(ipconfig getifaddr "$DEV" 2>/dev/null)
sketchybar --set wifi.status label="Wi-Fi: ${POWER:-?}"
sketchybar --set wifi.ip     label="IP: ${IP:-not connected}"
sketchybar --set wifi.toggle label="Turn Wi-Fi $([ "$POWER" = "On" ] && echo Off || echo On)"
sketchybar --set wifi popup.drawing=toggle
