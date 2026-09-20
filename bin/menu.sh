#!/usr/bin/env bash
# The Omarchy menu -- upstream's omarchy-menu, on ⌥O.
#
# Upstream binds SUPER+ALT+SPACE. Here ⌥ is SUPER and ⌥⌘Space is already macOS's
# "Show Finder search window", so this diverges deliberately: ⌥O for Omarchy.
#
# Takes an optional route, so `menu.sh style` opens straight into Style and
# `menu.sh theme` resolves the alias first -- the same shape as
# `omarchy menu summon style.theme`.
BIN="$HOME/.local/bin"
PICKER="$HOME/.local/share/omarchy-mac/OmarchyPicker.app/Contents/MacOS/omarchy-picker"

source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null

AEROSPACE=$(command -v aerospace || echo /opt/homebrew/bin/aerospace)
ws_before="${OMARCHY_WORKSPACE:-}"
[ -z "$ws_before" ] && [ -x "$AEROSPACE" ] && \
  ws_before=$("$AEROSPACE" list-workspaces --focused </dev/null 2>/dev/null)
export OMARCHY_WORKSPACE="$ws_before"

route="${1:-root}"
if [ "$route" != "root" ]; then
  resolved=$(python3 "$BIN/menu.py" resolve "$route" 2>/dev/null)
  [ -n "$resolved" ] && route="$resolved"
fi

if [ ! -x "$PICKER" ]; then
  echo "omarchy-menu: picker not built (run install.sh)" >&2
  exit 1
fi

choice=$(python3 "$BIN/menu.py" rows "$route" | "$PICKER" --menu "$BIN/menu.py" \
  --corpus "$BIN/menu.py" \
  --workspace "$ws_before" \
  --background "${BG:-0xff101315}" --foreground "${FG:-0xffcacccc}" \
  --accent "${ACCENT:-0xff798186}" --dark-background "${DARKBG:-0xff0c0e10}")
rc=$?

# The menu prints an id, never a command. menu.py looks the action up again and
# runs it -- nothing from the overlay is ever handed to a shell.
if [ $rc -eq 0 ] && [ -n "$choice" ]; then
  python3 "$BIN/menu.py" run "$choice"
fi

[ -n "$ws_before" ] && (python3 "$BIN/theme.py" _keep-workspace "$ws_before" >/dev/null 2>&1 &)
