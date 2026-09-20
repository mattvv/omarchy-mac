#!/usr/bin/env bash
# Left click: the theme picker. Right click: backgrounds for the current theme.
# Both are the same pickers as ⌥⌃⇧Space / ⌥⌃Space.
case "$BUTTON" in
  right) exec "$HOME/.local/bin/bg_menu.sh" ;;
  *)     exec "$HOME/.local/bin/theme_menu.sh" ;;
esac
