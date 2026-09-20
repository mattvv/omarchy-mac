#!/usr/bin/env bash
# OPTIONAL: build and install a fork of AeroSpace that adds a real `scrolling`
# workspace layout (plus `tabs`), the way Hyprland/Omarchy does it.
#
# Stock AeroSpace has only tiles / accordion / floating, so the base setup
# approximates scrolling with a horizontal accordion. This replaces that with
# the real thing: a horizontal strip of pages you scroll through, with a
# configurable peek at the next page.
#
# Upstream: https://github.com/nikitabobko/AeroSpace/pull/2057 (vadika) --
# unmerged at time of writing. Fork adds the peek on top.
#
# Reversible: revert-aerospace-fork.sh restores the Homebrew build.
set -euo pipefail

FORK_REPO="${AEROSPACE_FORK_REPO:-https://github.com/mattvv/AeroSpace.git}"
FORK_BRANCH="${AEROSPACE_FORK_BRANCH:-scrolling-layout}"
SRC="${AEROSPACE_FORK_SRC:-$HOME/Documents/AeroSpace}"
PEEK="${AEROSPACE_PEEK_WIDTH:-40}"
BACKUP="$SRC/.stock-backup"

say() { printf '\033[1;36m==>\033[0m %s\n' "$1"; }

command -v xcodebuild >/dev/null || { echo "Xcode required (xcodebuild not found)."; exit 1; }
# The build scripts hard-require bash 5; macOS ships 3.2.
if [ ! -x /opt/homebrew/bin/bash ]; then
  say "Installing bash 5 (build scripts require it; macOS ships 3.2)"
  brew install bash
fi
export PATH="/opt/homebrew/bin:$PATH"

if [ -d "$SRC/.git" ]; then
  say "Updating $SRC"
  git -C "$SRC" fetch --all -q
  git -C "$SRC" checkout -q "$FORK_BRANCH"
else
  say "Cloning $FORK_REPO"
  git clone -q --branch "$FORK_BRANCH" "$FORK_REPO" "$SRC"
fi
cd "$SRC"

# NOTE: generate.sh writes the codesign identity into xcode/AeroSpace.xcodeproj.
# The committed pbxproj hardcodes `aerospace-codesign-certificate`, which exists
# on no machine but the maintainer's. Do NOT `git checkout` that file after
# generating, or the Xcode build fails with "No certificate matching ...".
say "Generating project (ad-hoc signing)"
./generate.sh --build-version 0.0.0-SNAPSHOT --codesign-identity - --generate-git-hash >/dev/null

say "Building app (Release)"
( cd xcode && xcodebuild build -scheme AeroSpace -destination "generic/platform=macOS" \
    -configuration Release -derivedDataPath .xcode-build >/dev/null )

say "Building CLI"
# No -warnings-as-errors: upstream's NWConnectionEx.swift trips
# [#StrictMemorySafety] on Swift < 6.4, and that file is not ours to patch.
swift build -c release --product aerospace >/dev/null

APP="$SRC/xcode/.xcode-build/Build/Products/Release/AeroSpace.app"
CLI="$SRC/.build/arm64-apple-macosx/release/aerospace"
[ -d "$APP" ] && [ -x "$CLI" ] || { echo "Build produced no artifacts"; exit 1; }
# Guard against the silent-stale-build trap: the app must be newer than the CLI
# build started, or we would install an old binary alongside a new client.
say "Built: $(basename "$APP") $(date -r "$APP/Contents/MacOS/AeroSpace" '+%H:%M')"

mkdir -p "$BACKUP"
if [ ! -d "$BACKUP/AeroSpace.app" ] && [ -d /Applications/AeroSpace.app ]; then
  say "Backing up stock app"
  cp -R /Applications/AeroSpace.app "$BACKUP/AeroSpace.app"
  cp -L "$(command -v aerospace)" "$BACKUP/aerospace-cli" 2>/dev/null || true
fi

say "Installing app + CLI together (mismatched versions cannot talk)"
osascript -e 'tell application "AeroSpace" to quit' 2>/dev/null || killall AeroSpace 2>/dev/null || true
/bin/sleep 2
rm -rf /Applications/AeroSpace.app
cp -R "$APP" /Applications/AeroSpace.app
CLI_DEST="$(command -v aerospace || echo /opt/homebrew/bin/aerospace)"
rm -f "$CLI_DEST"; cp "$CLI" "$CLI_DEST"; chmod +x "$CLI_DEST"

# Fork-only config. Stock AeroSpace REJECTS these (unknown key / unknown
# command), so they are added only once the fork is installed.
CFG="$HOME/.aerospace.toml"
if ! grep -q "scrolling-peek-width" "$CFG" 2>/dev/null; then
  say "Adding fork-only config to $CFG"
  python3 - "$CFG" "$PEEK" <<'PY'
import sys, re
cfg, peek = sys.argv[1], sys.argv[2]
s = open(cfg).read()
if "scrolling-peek-width" not in s:
    s = s.replace("[key-mapping]", f"""# --- AeroSpace scrolling fork only ---
# Points of the NEXT page kept visible at the right edge in the scrolling
# layout. Auto-suppressed when a monitor sits to the right (a window manager
# cannot clip windows). Remove this if you revert to stock AeroSpace.
scrolling-peek-width = {peek}

[key-mapping]""", 1)
if "'scroll left'" not in s:
    s = s.replace("    # Modes", """    # Scrolling layout viewport (fork only). Arrows keep their directional
    # `focus` meaning; ctrl moves the viewport a page.
    alt-ctrl-left  = 'scroll left'
    alt-ctrl-right = 'scroll right'

    # Modes""", 1)
open(cfg, "w").write(s)
PY
fi

say "Launching"
open -a /Applications/AeroSpace.app
cat <<'DONE'

Installed the scrolling fork.

  1. Re-grant Accessibility if window management misbehaves:
     System Settings -> Privacy & Security -> Accessibility -> toggle AeroSpace off/on.

  2. `brew upgrade` WILL silently revert this to stock AeroSpace, and stock
     will then REFUSE your config (scrolling-peek-width / scroll are unknown).
     Re-run this script, or run revert-aerospace-fork.sh first.

Use it:
  Option+L            cycle dwindle -> scrolling -> tabs
  Option+Ctrl+Left    scroll the viewport left
  Option+Ctrl+Right   scroll the viewport right
DONE
