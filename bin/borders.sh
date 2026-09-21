#!/usr/bin/env bash
# Start JankyBorders in the current theme.
#
# Colours and corner style both come from the generated theme.sh, so there is
# one source of truth. Previously aerospace.toml carried a hardcoded borders
# command with Solitude's gradient in it, which was wrong the moment anyone
# switched theme -- and, because exec-and-forget goes through a shell, its
# unescaped parens meant it had never run at all.
set -uo pipefail
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
BORDERS=$(command -v borders || echo /opt/homebrew/bin/borders)
[ -x "$BORDERS" ] || exit 0

# Most Omarchy themes are square: upstream's Hyprland default is rounding = 0
# and only solitude overrides it. macOS rounds every window itself, though, so
# a square border only reads as square if JankyBorders insets it over the OS
# corner -- and that inset is gated on order=above AND width >= BORDER_TSMW
# (border.c:123-130). At the defaults -- order=below, width=4.0 -- it never ran,
# so square drew a bare rectangle across rounded glass. Brave showed it worst,
# Chromium's corner radius being larger than Ghostty's. Square therefore asks
# for the inset explicitly; round keeps the upstream default, which already
# traced the window correctly.
#
# BORDER_TSMW is 8.0 unless borders was built against the macOS 26 SDK, where
# it is 52.0. If a future bottle flips that, square silently returns to the bare
# rectangle -- the symptom to look for. Checked against v1.8.4.
if [ "${ROUNDING:-0}" -gt 0 ] 2>/dev/null; then
  style=round  width=4.0 order=below
else
  style=square width=8.0 order=above
fi

# `pkill -x borders`, not `-f`: an -f pattern would match this script's own
# command line and kill the shell doing the killing.
pkill -x borders 2>/dev/null
# nohup rather than setsid -- macOS does not ship setsid, and a script that
# silently starts nothing is worse than one that fails loudly.
nohup "$BORDERS" \
  active_color="${BORDER_ACTIVE:-0xff798186}" \
  inactive_color="${BORDER_INACTIVE:-0xff1e1e1e}" \
  width="$width" style="$style" order="$order" >/dev/null 2>&1 &
