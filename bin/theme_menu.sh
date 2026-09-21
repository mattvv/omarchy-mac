#!/usr/bin/env bash
# Omarchy SUPER+SHIFT+CTRL+SPACE equivalent: the full-screen theme picker.
#
# Same contract as omarchy's `theme=$(omarchy-theme-switcher); omarchy-theme-set
# "$theme"` -- the picker only prints a name, this applies it.
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

# Picker chrome is drawn in the theme you are currently wearing.
source "$HOME/.config/sketchybar/theme.sh" 2>/dev/null
# Read the state file rather than starting an interpreter for one line: every
# millisecond here is blank screen, and blank screen is where focus escapes.
current=$(cat "$HOME/.local/state/omarchy-mac/current-theme" 2>/dev/null)

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
  --workspace "$ws_before" \
  --radius "${ROUNDING:-0}" \
  --background "${BG:-0xff101315}" --foreground "${FG:-0xffcacccc}" \
  --accent "${ACCENT:-0xff798186}" --dark-background "${DARKBG:-0xff0c0e10}")
rc=$?

if [ -z "$choice" ]; then
  restore_workspace
  exit 0
fi

case $rc in
  0) python3 "$BIN/theme.py" set "$choice" >/dev/null; restore_workspace ;;
  # ⌘B: wear the theme first, then go straight into its backgrounds -- picking
  # a background for a theme you are not looking at makes no sense. Restore
  # before handing over, or bg_menu.sh inherits the wrong idea of "here".
  3) python3 "$BIN/theme.py" set "$choice" >/dev/null; restore_workspace
     exec "$BIN/bg_menu.sh" ;;
  *) restore_workspace ;;
esac
