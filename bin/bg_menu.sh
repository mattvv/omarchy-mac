#!/usr/bin/env bash
# Omarchy SUPER+CTRL+SPACE equivalent: pick a background for the current theme.
#
# omarchy's background switcher shows no labels and no filter -- you are looking
# at pictures, not names -- so this doesn't either.
BIN="$HOME/.local/bin"
PICKER="$HOME/.local/share/omarchy-mac/OmarchyPicker.app/Contents/MacOS/omarchy-picker"

# AeroSpace follows macOS focus. Close the picker on a workspace that has no
# windows of its own and macOS has nothing there to focus, so it hands focus to
# some app on another workspace and AeroSpace goes with it -- you pick a theme
# on an empty workspace 3 and land on 1. Remember where we were and come back.
# (Absolute fallback: a script launched from Raycast or the bar does not get
# your shell's PATH.)
AEROSPACE=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
# A launcher that ran before us read this earlier than we can -- see the
# generated Raycast commands. Its answer is the trustworthy one.
ws_before="${OMARCHY_WORKSPACE:-}"
[ -z "$ws_before" ] && [ -x "$AEROSPACE" ] && \
  ws_before=$("$AEROSPACE" list-workspaces --focused </dev/null 2>/dev/null)
export OMARCHY_WORKSPACE="$ws_before"

# One immediate check is not enough: AeroSpace's focus-follow can land after we
# have already looked and come back. theme.py's helper retries on a schedule and
# detaches, so it outlives this script.
restore_workspace() {
  [ -n "$ws_before" ] || return 0
  (python3 "$BIN/theme.py" _keep-workspace "$ws_before" >/dev/null 2>&1 &)
}

source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
theme=$(python3 "$BIN/theme.py" current)

# Top up the gallery in the background: `rows backgrounds` below already fetches
# synchronously when the theme has nothing at all, so this only ever runs ahead
# of the *next* open and never keeps the picker off the screen.
(python3 "$BIN/theme.py" fetch "$theme" >/dev/null 2>&1 &)

if [ ! -x "$PICKER" ]; then
  python3 "$BIN/theme.py" bg next
  exit 0
fi

choice=$(python3 "$BIN/theme.py" rows backgrounds "$theme" | "$PICKER" \
  --selected "$(python3 "$BIN/theme.py" bg current "$theme")" \
  --hint "←→  browse      ⏎  set background      esc  cancel" \
  --background "${BG:-0xff101315}" --foreground "${FG:-0xffcacccc}" \
  --accent "${ACCENT:-0xff798186}" --dark-background "${DARKBG:-0xff0c0e10}")

rc=$?
[ $rc -eq 0 ] && [ -n "$choice" ] && python3 "$BIN/theme.py" bg set "$choice"
restore_workspace
