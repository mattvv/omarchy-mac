#!/usr/bin/env bash
# Restore stock AeroSpace and strip the fork-only config keys.
set -euo pipefail
SRC="${AEROSPACE_FORK_SRC:-$HOME/Documents/AeroSpace}"
BACKUP="$SRC/.stock-backup"
CFG="$HOME/.aerospace.toml"

osascript -e 'tell application "AeroSpace" to quit' 2>/dev/null || killall AeroSpace 2>/dev/null || true
/bin/sleep 2

if [ -d "$BACKUP/AeroSpace.app" ]; then
  rm -rf /Applications/AeroSpace.app
  cp -R "$BACKUP/AeroSpace.app" /Applications/AeroSpace.app
  if [ -f "$BACKUP/aerospace-cli" ]; then
    DEST="$(command -v aerospace || echo /opt/homebrew/bin/aerospace)"
    rm -f "$DEST"; cp "$BACKUP/aerospace-cli" "$DEST"; chmod +x "$DEST"
  fi
else
  echo "No backup found; reinstalling from Homebrew"
  brew reinstall --cask aerospace
fi

# Stock AeroSpace refuses to load a config containing fork-only keys.
python3 - "$CFG" <<'PY'
import sys, re
cfg = sys.argv[1]
s = open(cfg).read()
s = re.sub(r"# --- AeroSpace scrolling fork only ---.*?scrolling-peek-width = \d+\n\n", "", s, flags=re.S)
s = re.sub(r"    # Scrolling layout viewport \(fork only\).*?alt-ctrl-right = 'scroll right'\n\n", "", s, flags=re.S)
open(cfg, "w").write(s)
PY

open -a /Applications/AeroSpace.app
echo "Reverted to stock AeroSpace and removed fork-only config keys."
