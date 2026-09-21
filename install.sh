#!/usr/bin/env bash
# Install the Omarchy-flavoured macOS setup. Idempotent: safe to re-run.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.config/omarchy-mac-backup-$(date +%Y%m%d-%H%M%S)"

say() { printf '\033[1;36m==>\033[0m %s\n' "$1"; }

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only."; exit 1; }
command -v brew >/dev/null || { echo "Homebrew required: https://brew.sh"; exit 1; }

say "Installing dependencies"
brew tap FelixKratz/formulae >/dev/null 2>&1 || true
brew tap nikitabobko/tap     >/dev/null 2>&1 || true
brew install --quiet sketchybar borders displayplacer blueutil || true
brew install --cask --quiet aerospace ghostty font-hack-nerd-font || true

say "Backing up existing config to $BACKUP"
mkdir -p "$BACKUP"
for f in "$HOME/.aerospace.toml" "$HOME/.wezterm.lua" \
         "$HOME/.config/ghostty/config" "$HOME/.config/sketchybar/sketchybarrc"; do
  [ -f "$f" ] && cp "$f" "$BACKUP/" 2>/dev/null || true
done

say "Installing config (substituting \$HOME)"
mkdir -p "$HOME/.config/ghostty" "$HOME/.config/sketchybar/plugins-omarchy"
sed "s|__HOME__|$HOME|g" "$REPO/config/aerospace.toml" > "$HOME/.aerospace.toml"
# The template cannot hold fork-only keys -- stock AeroSpace rejects unknown
# keys outright -- so they are re-applied here, after the file is written.
"$REPO/bin/aerospace_fork_config.sh" >/dev/null 2>&1 || true
cp "$REPO/config/wezterm.lua"              "$HOME/.wezterm.lua"
cp "$REPO/config/ghostty/config"           "$HOME/.config/ghostty/config"
cp "$REPO/config/sketchybar/sketchybarrc"  "$HOME/.config/sketchybar/sketchybarrc"
chmod +x "$HOME/.config/sketchybar/sketchybarrc"
for f in "$REPO"/config/sketchybar/plugins/*; do
  sed "s|__HOME__|$HOME|g" "$f" > "$HOME/.config/sketchybar/plugins-omarchy/$(basename "$f")"
done
chmod +x "$HOME"/.config/sketchybar/plugins-omarchy/*

say "Installing theme switcher"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/omarchy-mac"
cp "$REPO/bin/theme.py" "$REPO/bin/theme_menu.sh" "$REPO/bin/bg_menu.sh" "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/theme.py" "$HOME/.local/bin/theme_menu.sh" "$HOME/.local/bin/bg_menu.sh"
rm -rf "$HOME/.local/share/omarchy-mac/themes"
cp -R "$REPO/themes" "$HOME/.local/share/omarchy-mac/themes"

say "Building the full-screen picker"
# A minimal .app bundle rather than a bare binary: the Info.plist is what gives
# the picker a bundle id for AeroSpace to match a floating rule on, and
# LSUIElement is what keeps a full-screen overlay out of the Dock and the
# ⌘Tab switcher.
APP="$HOME/.local/share/omarchy-mac/OmarchyPicker.app"
if command -v swiftc >/dev/null 2>&1; then
  mkdir -p "$APP/Contents/MacOS"
  cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.omarchy-mac.picker</string>
  <key>CFBundleName</key><string>Omarchy Picker</string>
  <key>CFBundleExecutable</key><string>omarchy-picker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
  if swiftc -O -o "$APP/Contents/MacOS/omarchy-picker" "$REPO/bin/omarchy-picker.swift" 2>/dev/null; then
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
  else
    echo "  build failed -- the list menu will be used instead"
  fi
else
  echo "  no swiftc found (xcode-select --install) -- the list menu will be used instead"
fi

# Where this was installed from, so the Update menu can come back to it.
printf '%s\n' "$REPO" > "$HOME/.local/share/omarchy-mac/repo"

say "Generating Raycast script commands"
python3 "$HOME/.local/bin/theme.py" raycast >/dev/null

python3 "$HOME/.local/bin/theme.py" set "${OMARCHY_THEME:-ristretto}" >/dev/null 2>&1 || true

say "Backgrounds"
# `theme.py set` above only pulled the first background inline. Fetch the whole
# set now so the background picker has something to show on its first open.
python3 "$HOME/.local/bin/theme.py" fetch "${OMARCHY_THEME:-ristretto}" 2>/dev/null || true

say "Freeing Cmd+Space from Spotlight (for Raycast)"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 '
<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key>
<array><integer>32</integer><integer>49</integer><integer>1048576</integer></array>
<key>type</key><string>standard</string></dict></dict>' 2>/dev/null || true
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true

# Optional: real scrolling layout (builds AeroSpace from source, needs Xcode).
# Off by default because it replaces a Homebrew-managed app with a source build.
if [ "${1:-}" = "--scrolling" ] || [ "${OMARCHY_SCROLLING:-0}" = "1" ]; then
  say "Installing the scrolling-layout fork"
  "$REPO/bin/install-aerospace-fork.sh"
fi

say "Starting services"
# Reload rather than kill-and-respawn: the replacement races sketchybar's lock
# file, loses, and leaves the old instance running with the old config.
if pgrep -x sketchybar >/dev/null 2>&1; then
  sketchybar --reload
else
  (sketchybar >/dev/null 2>&1 &)
fi
pkill -x borders 2>/dev/null || true
(borders active_color=gradient\(top_left=0xff798186,bottom_right=0xffcacccc\) \
         inactive_color=0xff1e1e1e width=4.0 >/dev/null 2>&1 &)
open -a AeroSpace 2>/dev/null || true

cat <<'DONE'

Installed. A few things still need YOUR hands (macOS will not let a script do them):

  1. System Settings -> Privacy & Security -> Accessibility
       enable AeroSpace   (window management)
       enable Ghostty     (its global Alt+Return hotkey)
  2. Raycast -> Settings -> General -> Raycast Hotkey -> press Cmd+Space
  3. Raycast -> Settings -> Extensions -> + -> Add Script Directory ->
       ~/.local/share/omarchy-mac/raycast
       (puts "Omarchy Theme", "Omarchy Background" and the pickers on Cmd+Space)
  4. Zed (optional): open the theme picker and choose "Omarchy" once. After that,
       every theme switch repaints Zed live and your settings.json is never touched.
  5. Log out / back in if Spotlight still owns Cmd+Space

Your previous config was backed up. See the path printed above.

Want Omarchy's real scrolling layout (stock AeroSpace has no such layout)?
  ./bin/install-aerospace-fork.sh      # or re-run: ./install.sh --scrolling
DONE
