# Setting this up on a fresh Mac

Instructions for Claude. The human cannot grant macOS permissions from a script — you must
stop and ask them at the marked points.

## Preconditions

- Apple Silicon, macOS 13+
- Homebrew installed
- **At least 5 GB free disk.** Check first: `df -h /System/Volumes/Data`

## 1. Run the installer

```sh
./install.sh
```

It installs dependencies, backs up existing config, substitutes `__HOME__`, downloads the
Solitude wallpapers, frees `Cmd+Space`, and starts the services. Re-running is safe.

## 2. Stop and ask the human

These cannot be automated — TCC prompts do not appear from background processes:

1. **Accessibility** for **AeroSpace** — without it, AeroSpace runs but its CLI blocks
   and no window management works.
2. **Accessibility** for **Ghostty** — needed for its global `⌥Return` hotkey.
3. **Raycast hotkey** — Raycast stores it internally; there is no writable pref. The human
   sets it in Raycast → Settings → General.

Open the pane for them:
`open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`

## 3. Verify

```sh
aerospace list-modes </dev/null          # expect: main, resize, service
sketchybar --query bar | python3 -c "import sys,json;print(len(json.load(sys.stdin)['items']))"
python3 ~/.config/sketchybar/plugins-omarchy/brightness.py   # expect a number

python3 ~/.local/bin/theme.py rows themes | wc -l   # expect 22 -- 0 means theme.py
                                                    # cannot see the palettes
ls ~/.local/share/omarchy-mac/OmarchyPicker.app/Contents/MacOS/omarchy-picker
OMARCHY_PICKER_DEBUG=1 ~/.local/bin/theme_menu.sh   # stderr must say
                                                    # app.isActive=true panel.isKey=true

# Picking is the one path you cannot screenshot. This applies the highlighted
# row unattended, so you can check it from another workspace and confirm you
# are still on that workspace afterwards:
aerospace workspace 6 </dev/null
OMARCHY_PICKER_DEBUG_SELECT=1 ~/.local/bin/theme_menu.sh
aerospace list-workspaces --focused </dev/null   # must still be 6
```

**A screenshot cannot tell you whether the picker has the keyboard.** It will look
perfect and eat every keystroke. `OMARCHY_PICKER_DEBUG=1` is the only check that answers
it — and note that `System Events`' "frontmost application process" is *blind* to an
`LSUIElement` app, so it reports the terminal and looks like a failure when there is
none.

**Always redirect stdin (`</dev/null`) for `aerospace` commands.** Without it the CLI can
block on a non-TTY stdin and look like a hang — this wastes a lot of time otherwise.

## 4. Optional per-machine tuning

- **Timezones** — `clock_popup.sh` has hardcoded cities. Ask which ones they want.
- **Apps** — `aerospace.toml` binds Brave, Zed, Spotify, 1Password. Verify each bundle
  exists (`ls -d "/Applications/<Name>.app"`) before keeping the binding.
- **Accordion peek** — `accordion-padding` in `aerospace.toml`, default 80.
- **AI panel** — needs Claude Code logged in; Codex needs the `codex` CLI (check mise:
  `mise which codex`, it is often not on a non-login shell's PATH).

## Traps

Each of these cost real time to diagnose. Don't repeat them.

- **`aerospace` appearing to hang** is almost always stdin, not a broken config or missing
  permission. Redirect `</dev/null` before concluding anything else.
- **Never `killall AeroSpace` to "fix" something.** Relaunching costs its Accessibility
  grant and needs a manual re-toggle. Validate the config instead:
  `python3 -c "import tomllib;tomllib.load(open('$HOME/.aerospace.toml','rb'))"`
- **`sketchybar --query` silently omits** `background`, popup `drawing`, and `notch_width`.
  Absence there is not evidence of failure — don't chase it.
- **sketchybar accepts invalid-in-practice properties without error.** `notch_width` returns
  rc=0 and does nothing; `notch_display_height` returns rc=0 and blanks the bar. A bogus
  property *does* error, so silence only proves the name exists.
- **Brightness**: only `DisplayServicesGet/SetBrightness` works. `brew install brightness`
  and both ioreg values are dead ends that return convincing but wrong numbers.
- **Setting a popup row's label later doesn't resize the popup.** Fixed `label.width` is
  required or text clips.

- **Notch placement is `q`/`e`, not `notch_width`.** Those are real sketchybar positions
  (left-of-notch / right-of-notch). `notch_width` is inert and `notch_display_height`
  blanks the bar — do not reach for them.
- **Never `pkill sketchybar` to apply a change.** It races the lock file and leaves the
  stale instance running. Use `sketchybar --reload`.
- **`theme.py` must find its palettes from either location.** Run from the repo they sit
  in `../themes`; installed into `~/.local/bin` they are in
  `~/.local/share/omarchy-mac/themes`. Resolving only the first left the installed copy
  pointing at `~/.local/themes` — `list`, `rows` and `set` then returned *nothing at all*,
  silently, and the bar's theme menu did nothing.
- **Upstream moved: `basecamp/omarchy` → `omacom/omarchy`**, default branch no longer
  `master`. Old `raw.githubusercontent.com/basecamp/...` URLs return 404 with no
  redirect; the `api.github.com/repos/.../contents/...` path still redirects correctly and
  hands back a current `download_url`. Backgrounds are mostly `.webp` now — glob for it.
- **Quickshell is Linux/BSD only.** Omarchy's picker is a Quickshell plugin whose overlay
  is a wlroots layer-shell surface. There is no macOS build and no equivalent protocol —
  don't go looking for one. `bin/omarchy-picker.swift` reimplements the design in AppKit.
- **A GUI launch gets none of your shell.** Raycast, sketchybar click scripts and
  AeroSpace `exec-and-forget` run with a bare PATH: Homebrew is not on it, and `python3`
  resolves to **`/usr/bin/python3`, which is 3.9** — so `import tomllib` (3.11+) raised
  `ModuleNotFoundError` and `theme.py` died before doing anything. It tests clean from a
  terminal and fails from every button. Reproduce it with
  `env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/bash <script>`, and resolve `sketchybar`,
  `borders`, `pgrep` and `osascript` through `tool()` rather than naming them bare.
- **The workspace guard belongs in `theme.py`, not only in the wrappers.** Raycast's
  dropdown command calls `theme.py set` directly and never touches `theme_menu.sh`, so a
  guard that lives only in the shell covers the pickers and misses the launcher.
- **Closing a window on an empty AeroSpace workspace moves you.** With nothing left to
  focus, macOS hands focus to an app on another workspace and AeroSpace follows — open the
  picker on an empty workspace 3 and closing it drops you on 1. The wrappers record
  `aerospace list-workspaces --focused` before opening and return to it afterwards; the
  picker also hands focus back to whatever app it interrupted.
- **A theme switch must also set macOS appearance** (`System Events` → `appearance
  preferences` → `dark mode`). Config files alone leave browsers and native apps wrong.

## Design decisions to preserve

- **Omarchy's SUPER maps to ⌥, never ⌘.** ⌘ would clobber ⌘W/T/F/S/L/1-9 system-wide.
- **Nothing lives in the bar's centre** — the notch would cover it and sketchybar's notch
  support does not work.
- **The AI panel must read the scoped `limits` array**, not just the flat buckets. A
  model-scoped weekly limit is frequently the highest utilisation, and reading buckets
  alone hides it.
- **Never print, log or cache the OAuth token** — Authorization header only.
- **The picker ships as a minimal `.app`, not a bare binary.** The Info.plist is what gives
  it a bundle id (`dev.omarchy-mac.picker`) for AeroSpace's `on-window-detected` floating
  rule to match, and `LSUIElement` is what keeps a full-screen overlay out of the Dock and
  `⌘Tab`. A bundle-less binary has no id to match on.
- **The picker prints, it does not apply.** `theme_menu.sh` runs the picker, gets a name on
  stdout and calls `theme.py set` — the same split as omarchy's
  `theme=$(omarchy-theme-switcher); omarchy-theme-set "$theme"`. Keep the picker generic:
  it is an image carousel that knows nothing about themes.
