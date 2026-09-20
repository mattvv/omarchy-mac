#!/usr/bin/env bash
DEV=$(networksetup -listallhardwareports 2>/dev/null \
      | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')
[ -z "$DEV" ] && DEV=en0
POWER=$(networksetup -getairportpower "$DEV" 2>/dev/null | grep -o "On\|Off")
if [ "$POWER" = "On" ]; then
  networksetup -setairportpower "$DEV" off
else
  networksetup -setairportpower "$DEV" on
fi
sleep 1
"$(dirname "$0")/wifi.sh"
