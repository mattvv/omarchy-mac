#!/bin/sh
# Omarchy SUPER+RETURN equivalent: a NEW Ghostty window.
# `open -na Ghostty` spawns a second app instance rather than a window, so
# activate the running instance and use its own Cmd+N instead.
if pgrep -x ghostty >/dev/null 2>&1; then
  osascript -e 'tell application "Ghostty" to activate' \
            -e 'tell application "System Events" to keystroke "n" using command down'
else
  open -a Ghostty
fi
