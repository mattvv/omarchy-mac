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
```

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

## Design decisions to preserve

- **Omarchy's SUPER maps to ⌥, never ⌘.** ⌘ would clobber ⌘W/T/F/S/L/1-9 system-wide.
- **Nothing lives in the bar's centre** — the notch would cover it and sketchybar's notch
  support does not work.
- **The AI panel must read the scoped `limits` array**, not just the flat buckets. A
  model-scoped weekly limit is frequently the highest utilisation, and reading buckets
  alone hides it.
- **Never print, log or cache the OAuth token** — Authorization header only.
