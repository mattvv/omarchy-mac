#!/usr/bin/env bash
# Omarchy SUPER+CTRL+SPACE equivalent: pick a background for the current theme.
#
# omarchy's background switcher shows no labels and no filter -- you are looking
# at pictures, not names -- so this doesn't either.
BIN="$HOME/.local/bin"
PICKER="$HOME/.local/share/omarchy-mac/OmarchyPicker.app/Contents/MacOS/omarchy-picker"

source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
theme=$(python3 "$BIN/theme.py" current)

# A theme switch only fetches the first background inline and leaves the rest to
# a detached fetch, so make sure the full set has landed before showing a picker
# that is meant to show all of them. It is a no-op once they are on disk.
python3 "$BIN/theme.py" fetch "$theme" >/dev/null 2>&1

if [ ! -x "$PICKER" ]; then
  python3 "$BIN/theme.py" bg next
  exit 0
fi

choice=$(python3 "$BIN/theme.py" rows backgrounds "$theme" | "$PICKER" \
  --selected "$(python3 "$BIN/theme.py" bg current "$theme")" \
  --hint "←→  browse      ⏎  set background      esc  cancel" \
  --background "${BG:-0xff101315}" --foreground "${FG:-0xffcacccc}" \
  --accent "${ACCENT:-0xff798186}" --dark-background "${DARKBG:-0xff0c0e10}")

[ $? -eq 0 ] && [ -n "$choice" ] && python3 "$BIN/theme.py" bg set "$choice"
