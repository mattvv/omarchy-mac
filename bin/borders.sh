#!/usr/bin/env bash
# Start JankyBorders in the current theme.
#
# Colours come from the generated theme.sh; corner style follows macOS windows,
# not the theme. Previously aerospace.toml carried a hardcoded borders
# command with Solitude's gradient in it, which was wrong the moment anyone
# switched theme -- and, because exec-and-forget goes through a shell, its
# unescaped parens meant it had never run at all.
set -uo pipefail
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
BORDERS=$(command -v borders || echo /opt/homebrew/bin/borders)
[ -x "$BORDERS" ] || exit 0

# Upstream's Hyprland rounding = 0 squares the window itself. macOS does not
# follow that setting -- JankyBorders' round style uses each window's reported
# radius. Keep theme rounding on our menu and bar, not on somebody else's window.
style=round

# `pkill -x borders`, not `-f`: an -f pattern would match this script's own
# command line and kill the shell doing the killing.
pkill -x borders 2>/dev/null
# nohup rather than setsid -- macOS does not ship setsid, and a script that
# silently starts nothing is worse than one that fails loudly.
nohup "$BORDERS" \
  active_color="${BORDER_ACTIVE:-0xff798186}" \
  inactive_color="${BORDER_INACTIVE:-0xff1e1e1e}" \
  width=4.0 style="$style" >/dev/null 2>&1 &
