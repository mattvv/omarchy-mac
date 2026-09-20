#!/usr/bin/env bash
# Omarchy SUPER+SHIFT+CTRL+SPACE equivalent: the full-screen theme picker.
#
# Same contract as omarchy's `theme=$(omarchy-theme-switcher); omarchy-theme-set
# "$theme"` -- the picker only prints a name, this applies it.
BIN="$HOME/.local/bin"
PICKER="$HOME/.local/share/omarchy-mac/OmarchyPicker.app/Contents/MacOS/omarchy-picker"

# Picker chrome is drawn in the theme you are currently wearing.
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
current=$(python3 "$BIN/theme.py" current)

if [ ! -x "$PICKER" ]; then
  # No compiled picker (no Swift toolchain at install time). A native
  # `choose from list` is ugly but keyboard-navigable and always available.
  python3 - "$BIN" <<'PY'
import subprocess, sys
bin_dir = sys.argv[1]
out = subprocess.run(["python3", bin_dir + "/theme.py", "list"],
                     capture_output=True, text=True).stdout
names, cur = [], ""
for line in out.splitlines():
    if not line.strip(): continue
    mark, name = line[0], line[1:].split()[0]
    names.append(name)
    if mark == "*": cur = name
lst = ", ".join('"%s"' % n for n in names)
script = (f'set t to {{{lst}}}\n'
          f'choose from list t with title "Omarchy theme" '
          f'with prompt "Current: {cur}" default items {{"{cur}"}}')
r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
choice = r.stdout.strip()
if choice and choice != "false":
    subprocess.run(["python3", bin_dir + "/theme.py", "set", choice])
PY
  exit 0
fi

choice=$(python3 "$BIN/theme.py" rows themes | "$PICKER" \
  --labels --filterable --chrome \
  --selected "$current" \
  --alt-key b \
  --hint "←→  browse      ⏎  apply      ⌘B  backgrounds      esc  cancel" \
  --background "${BG:-0xff101315}" --foreground "${FG:-0xffcacccc}" \
  --accent "${ACCENT:-0xff798186}" --dark-background "${DARKBG:-0xff0c0e10}")
rc=$?

[ -z "$choice" ] && exit 0
case $rc in
  0) python3 "$BIN/theme.py" set "$choice" >/dev/null ;;
  # ⌘B: wear the theme first, then go straight into its backgrounds -- picking
  # a background for a theme you are not looking at makes no sense.
  3) python3 "$BIN/theme.py" set "$choice" >/dev/null; exec "$BIN/bg_menu.sh" ;;
esac
