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
cp "$REPO/bin/theme.py" "$REPO/bin/theme_menu.sh" "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/theme.py" "$HOME/.local/bin/theme_menu.sh"
rm -rf "$HOME/.local/share/omarchy-mac/themes"
cp -R "$REPO/themes" "$HOME/.local/share/omarchy-mac/themes"
python3 "$HOME/.local/bin/theme.py" set "${OMARCHY_THEME:-solitude}" >/dev/null 2>&1 || true

say "Wallpapers (fallback)"
mkdir -p "$HOME/Pictures/omarchy-solitude"
if [ -z "$(ls -A "$HOME/Pictures/omarchy-solitude" 2>/dev/null)" ]; then
  OM="https://raw.githubusercontent.com/basecamp/omarchy/master/themes/solitude/backgrounds"
  for w in 1-on-pole 2-wreakage 3-climb 4-ether 5-eyed; do
    curl -fsSL "$OM/$w.jpg" -o "$HOME/Pictures/omarchy-solitude/$w.jpg" || true
  done
  [ -f "$HOME/Pictures/omarchy-solitude/1-on-pole.jpg" ] && \
    osascript -e "tell application \"System Events\" to set picture of every desktop to \"$HOME/Pictures/omarchy-solitude/1-on-pole.jpg\"" || true
fi

say "Freeing Cmd+Space from Spotlight (for Raycast)"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 '
<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key>
<array><integer>32</integer><integer>49</integer><integer>1048576</integer></array>
<key>type</key><string>standard</string></dict></dict>' 2>/dev/null || true
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true

say "Starting services"
pkill -x sketchybar 2>/dev/null || true; sleep 1
(sketchybar >/dev/null 2>&1 &)
pkill -x borders 2>/dev/null || true
(borders active_color=gradient\(top_left=0xff798186,bottom_right=0xffcacccc\) \
         inactive_color=0xff1e1e1e width=4.0 >/dev/null 2>&1 &)
open -a AeroSpace 2>/dev/null || true

cat <<'DONE'

Installed. Three things still need YOUR hands (macOS will not let a script do them):

  1. System Settings -> Privacy & Security -> Accessibility
       enable AeroSpace   (window management)
       enable Ghostty     (its global Alt+Return hotkey)
  2. Raycast -> Settings -> General -> Raycast Hotkey -> press Cmd+Space
  3. Log out / back in if Spotlight still owns Cmd+Space

Your previous config was backed up. See the path printed above.
DONE
