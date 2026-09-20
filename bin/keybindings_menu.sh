#!/usr/bin/env bash
# The keybindings reference, in the menu's list overlay.
#
# A reference card, not a dispatcher: upstream's version *runs* the binding you
# pick, which does not survive the translation. By the time this overlay closes,
# "close window" would act on whatever gained focus, `mode resize` would leave
# you in a mode with nothing on screen to say so, and every row is an array
# whose first command is a poor description of the whole. So nothing here runs.
BIN="$HOME/.local/bin"
PICKER="$HOME/.local/share/omarchy-mac/OmarchyPicker.app/Contents/MacOS/omarchy-picker"

source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
AEROSPACE=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
ws_before="${OMARCHY_WORKSPACE:-}"
[ -z "$ws_before" ] && [ -x "$AEROSPACE" ] && \
  ws_before=$("$AEROSPACE" list-workspaces --focused </dev/null 2>/dev/null)

python3 "$BIN/keybindings.py" rows | "$PICKER" --menu "$BIN/keybindings.py" \
  --workspace "$ws_before" \
  --background "${BG:-0xff101315}" --foreground "${FG:-0xffcacccc}" \
  --accent "${ACCENT:-0xff798186}" --dark-background "${DARKBG:-0xff0c0e10}" >/dev/null

[ -n "$ws_before" ] && (python3 "$BIN/theme.py" _keep-workspace "$ws_before" >/dev/null 2>&1 &)
exit 0
