#!/usr/bin/env bash
# Highlight the focused AeroSpace workspace.
# Queries aerospace directly so it is correct on startup, on --update, and on
# the aerospace_workspace_change event alike (the event's env var is not
# delivered on every invocation).
SID="$1"
FG=0xffcacccc
MUTED=0xff4b4e55
SEL=0xff343d41

FOCUS="${FOCUSED_WORKSPACE:-$FOCUSED}"
if [ -z "$FOCUS" ]; then
  FOCUS=$(/opt/homebrew/bin/aerospace list-workspaces --focused </dev/null 2>/dev/null)
fi

if [ "$SID" = "$FOCUS" ]; then
  sketchybar --set "$NAME" \
    background.drawing=on background.color=$SEL \
    background.corner_radius=5 background.height=24 \
    label.color=$FG
else
  sketchybar --set "$NAME" background.drawing=off label.color=$MUTED
fi
