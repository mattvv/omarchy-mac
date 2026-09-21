#!/usr/bin/env bash
# Update the setup from the repo it was installed from.
#
# `git pull && ./install.sh` reinstalls configs and restarts services, so it
# runs in a visible terminal rather than silently from a menu: an update that
# fails quietly is worse than one that never ran.
set -uo pipefail
REPO_FILE="$HOME/.local/share/omarchy-mac/repo"
GHOSTTY="/Applications/Ghostty.app/Contents/MacOS/ghostty"

repo() {
  # Recorded by install.sh; the fallback is only for a setup installed before
  # that existed.
  [ -f "$REPO_FILE" ] && cat "$REPO_FILE" || echo "$HOME/Documents/omarchy-mac"
}

in_terminal() {
  if [ -x "$GHOSTTY" ]; then
    "$GHOSTTY" -e /bin/bash -lc "$1" >/dev/null 2>&1 &
  else
    osascript -e "tell application \"Terminal\" to do script \"$1\"" >/dev/null 2>&1
  fi
}

case "${1:-status}" in
  status)
    r=$(repo)
    [ -d "$r/.git" ] || { echo "no repo at $r"; exit 1; }
    echo "$(basename "$r") $(git -C "$r" rev-parse --short HEAD) on $(git -C "$r" branch --show-current)" ;;
  omarchy)
    r=$(repo)
    [ -d "$r/.git" ] || { echo "no repo at $r" >&2; exit 1; }
    in_terminal "cd '$r' && git pull && ./install.sh; echo; echo 'Press return to close.'; read -r _" ;;
  config)
    r=$(repo); name="${2:-}"
    case "$name" in
      aerospace)  sed "s|__HOME__|$HOME|g" "$r/config/aerospace.toml" > "$HOME/.aerospace.toml"
                  # Regenerating drops the fork-only keys; put them back before
                  # reloading, or the scrolling peek quietly disappears.
                  "$r/bin/aerospace_fork_config.sh" >/dev/null 2>&1 || true
                  aerospace reload-config </dev/null >/dev/null 2>&1 ;;
      ghostty)    cp "$r/config/ghostty/config" "$HOME/.config/ghostty/config" ;;
      wezterm)    cp "$r/config/wezterm.lua" "$HOME/.wezterm.lua" ;;
      sketchybar) cp "$r/config/sketchybar/sketchybarrc" "$HOME/.config/sketchybar/sketchybarrc"
                  for f in "$r"/config/sketchybar/plugins/*; do
                    sed "s|__HOME__|$HOME|g" "$f" > "$HOME/.config/sketchybar/plugins-omarchy/$(basename "$f")"
                  done
                  chmod +x "$HOME"/.config/sketchybar/plugins-omarchy/*
                  sketchybar --reload >/dev/null 2>&1 ;;
      menu)       cp "$r/config/menu.jsonc" "$HOME/.local/share/omarchy-mac/menu.jsonc" ;;
      *) echo "usage: update.sh config [aerospace|ghostty|wezterm|sketchybar|menu]" >&2; exit 2 ;;
    esac
    echo "reinstalled $name" ;;
  *) echo "usage: update.sh [status|omarchy|config <name>]" >&2; exit 2 ;;
esac
