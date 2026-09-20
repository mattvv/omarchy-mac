#!/usr/bin/env bash
# Keep the Mac awake, as a toggle the menu can also report the state of.
#
# Deliberately not `pkill -f caffeinate`: the shell running that command has the
# pattern in its own argv, so pkill matches the process doing the killing and
# the toggle kills itself. Ask for a pid file instead, and nothing has to be
# guessed from a command line.
PIDFILE="$HOME/.cache/omarchy-mac/stay-awake.pid"

running() {
  [ -f "$PIDFILE" ] || return 1
  local pid; pid=$(cat "$PIDFILE" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

case "${1:-toggle}" in
  status)  running && { echo on; exit 0; } || { echo off; exit 1; } ;;
  on)      running && exit 0
           mkdir -p "$(dirname "$PIDFILE")"
           caffeinate -dimsu >/dev/null 2>&1 &
           echo $! > "$PIDFILE" ;;
  off)     running && kill "$(cat "$PIDFILE")" 2>/dev/null; rm -f "$PIDFILE" ;;
  toggle)  if running; then "$0" off; else "$0" on; fi ;;
  *)       echo "usage: stay_awake.sh [toggle|on|off|status]" >&2; exit 2 ;;
esac
