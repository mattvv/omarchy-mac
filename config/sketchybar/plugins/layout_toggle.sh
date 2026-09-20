#!/usr/bin/env bash
# Omarchy SUPER+L equivalent.
#
# With the scrolling fork installed (see bin/install-aerospace-fork.sh):
#     dwindle -> scrolling -> tabs -> dwindle
# On stock AeroSpace, which has no scrolling/tabs layouts:
#     dwindle -> accordion -> dwindle        (accordion is the nearest analogue)
#
# Reads the CURRENT layout from aerospace rather than a cache file: a cache
# goes stale the moment anything else changes the layout, and the cycle then
# jumps to the wrong place. `%{window-layout}` is the source of truth.
AS=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
STATE="$HOME/.cache/omarchy-layout"

# The `scroll` subcommand exists only in the fork, and `layout --help` does
# not enumerate layouts -- so this is the reliable marker.
has_scrolling() { "$AS" --help </dev/null 2>&1 | grep -qE "^[[:space:]]+scroll[[:space:]]"; }

CUR=$("$AS" list-windows --focused --format '%{window-layout}' </dev/null 2>/dev/null | head -1)

if has_scrolling; then
  case "$CUR" in
    h_tiles|v_tiles|tiles) NEW=scrolling ;;
    scrolling)             NEW=tabs      ;;
    *)                     NEW=tiles     ;;
  esac
else
  case "$CUR" in
    h_tiles|v_tiles|tiles) NEW=h_accordion ;;
    *)                     NEW=tiles       ;;
  esac
fi

if "$AS" layout "$NEW" </dev/null >/dev/null 2>&1; then
  echo "$NEW" > "$STATE"
else
  # `layout scrolling` is rejected unless the focused node is the root
  # container; fall back rather than record a state we are not in.
  "$AS" layout tiles </dev/null >/dev/null 2>&1 && echo tiles > "$STATE"
fi
sketchybar --trigger layout_change
