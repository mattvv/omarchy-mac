# omarchy-menu for macOS — working plan

Upstream Omarchy has **two** launchers: `walker` opens apps, and `omarchy-menu`
(`SUPER+ALT+SPACE`) is its own keyboard-driven system menu. We mapped walker → Raycast but
wrongly put system actions (theme, background) in Raycast too — which is how focus kept
escaping the workspace, since Raycast dismisses its own window and we cannot control that.

This builds our own menu. Upstream's definition is 340 entries over 10 groups
(`default/omarchy/omarchy-menu.jsonc`); a large part of `install`/`remove` is pacman/AUR and
has no honest macOS equivalent. Each item below says what we build, or why we don't.

**Ground rules** (learned the hard way, see CLAUDE.md):
- Nothing ships without a test that would fail if the feature were absent.
- A workspace timeline that never moves proves nothing unless `pgrep -f OmarchyPicker`
  confirms the window existed.
- Everything must run under `/usr/bin/python3` (3.9) with `PATH=/usr/bin:/bin` — that is
  what a GUI launch gets. Reproduce with `env -i HOME="$HOME" PATH=/usr/bin:/bin`.
- Verify visually with `screencapture` before claiming a UI works.

---

## P0 — the menu engine

- [x] `--menu` list mode in `bin/omarchy-picker.swift`: NSTableView + NSSearchField,
      AppKit's own field editor, IME-safe navigation, `performKeyEquivalent` for ⌘A/C/V
      since a bundle-less app has no Edit menu
- [x] `config/menu.jsonc` — upstream's schema: dotted ids imply hierarchy, `action` → run,
      otherwise submenu; `icon`, `label`, `aliases`, `when`, `checked`
- [x] `bin/menu.py` — JSONC parse under Python 3.9, route resolution, dispatch
- [x] `bin/menu.sh` — wrapper, `OMARCHY_WORKSPACE` capture, restore guard
- [x] Submenu descent in place — the process stays alive and reloads rows from `menu.py`,
      so a three-deep menu does not pay the close-excursion three times.
      **Not keyboard-verified**: descending needs a keypress, which cannot be driven
      without typing into a live session. The backend call it makes is tested.
- [x] Keybindings: ⌘Space opens the menu, ⌥O also does, ⌥K opens the keybindings
      reference. ⌘Space means the menu is the launcher, so a query searches the whole
      tree *and* every installed app (123 here) rather than the level you are standing on.
      Raycast keeps ⌥Space; its own ⌘Space hotkey has to be moved by hand in Raycast →
      Settings → General, since it stores it internally with nothing readable on disk.
- [x] Bar: the leftmost logo opens the menu. It had been wired to `open -a Raycast` —
      the same mistake of treating the launcher as the system menu.

## P1 — style  (upstream: 20 entries)

- [x] `style.theme` → existing theme picker, reached from the menu
- [x] `style.background` → existing background picker, plus Next Background
- [ ] `style.font` → pick a terminal font, write to Ghostty + WezTerm theme files
- [x] `style.bar.position` → top / bottom, applied live and remembered across reloads.
      Left and right are absent: sketchybar is a horizontal bar, and a row that turns it
      sideways would be a row that does nothing.
- [x] `style.bar.transparency` → solid / translucent / transparent, swapping the alpha
      byte of whatever colour the current theme set
- [ ] `style.about` / `style.screensaver` → macOS screen saver module + text

## P2 — system  (upstream: 7 entries, all map)

All six are in the menu and their commands are checked to exist by the test suite.
They are **not executed** in tests, for obvious reasons — a test that verifies
Shutdown works is a test you run once.

- [x] `system.lock` → `pmset displaysleepnow` (CGSession is gone in macOS 15)
- [x] `system.suspend` → `pmset sleepnow`
- [x] `system.logout` / `reboot` / `shutdown` → osascript System Events
- [x] `system.screensaver` → `open -a ScreenSaverEngine`
- [x] `system.hibernate` → absent: Apple Silicon has no hibernate

## P3 — learn  (upstream: 9 entries) — includes the keybindings app

- [x] **Keybindings viewer** — `bin/keybindings.py` + `bin/keybindings_menu.sh`. Reads the
      installed `~/.aerospace.toml` (82 bindings, 3 modes) and Ghostty's
      `keybind = global:` lines; renders chords in canonical macOS order (⌃⌥⇧⌘) with
      glyphs only where they are universally read; describes commands by *shape*, never by
      chord, and shows anything unrecognised raw rather than guessing.
      **It does not run what you pick** — a deliberate divergence from upstream, which
      does. By the time the overlay closes, `close` would act on whatever gained focus and
      `mode resize` would strand you in a mode with nothing on screen to say so. Enforced
      in both layers: the overlay never prints a `kb:` id and `menu.py run` refuses them.
      Raycast's hotkey is shown as an explicit *unverified* note, never as a chord —
      it keeps it internally with nothing readable on disk.
- [ ] Doc links: Omarchy, AeroSpace (in place of Hyprland), macOS, Neovim, Bash, Tmux

## P4 — trigger  (upstream: 46 entries)

- [x] `trigger.screenshot` → `screencapture -i`, region and window
- [x] `trigger.screenrecord` → `screencapture -v`. Audio variants need ffmpeg-class
      tooling macOS does not ship; not ported.
- [x] `trigger.color` → Digital Color Meter
- [ ] `trigger.capture.text` → macOS Live Text OCR via Vision framework
- [ ] `trigger.emoji` → macOS emoji palette (`⌃⌘Space`)
- [x] `trigger.stay-awake` → `caffeinate` behind a pid file, with a live ✓ on the row
- [ ] `trigger.toggle.nightlight` → **no macOS CLI.** Needs `brew install nightlight`
      or a private-framework call; no row until one of those is decided.
- [ ] `trigger.toggle.notifications` → Focus has no supported CLI. A user-made
      Shortcut plus `shortcuts run` is the only honest route; needs their input.
- [x] `trigger.toggle.top-bar` → `sketchybar --bar hidden=toggle`, under Style › Menu Bar
- [ ] `trigger.share.*` → AirDrop / `shortcuts` share sheet
- [ ] `trigger.hardware.mirror-display` → `displayplacer` is installed, but this Mac
      has one display, so there is nothing to mirror and nothing to test against.

## P5 — setup  (upstream: 66 entries)

- [x] `setup.monitors` → opens the Displays pane. `displayplacer` can *restore* a
      saved arrangement but cannot present one to choose, and this Mac has one
      display to test against.
- [x] `setup.keybindings` → opens `~/.aerospace.toml`; `setup.config.*` opens the
      Ghostty, bar and menu configs
- [x] `setup.input` / `setup.trackpad` → the Keyboard and Trackpad panes. Writing
      these with `defaults` needs a logout to take effect and silently disagrees
      with the UI until then; opening the pane is the honest equivalent.
- [x] `setup.dns` → DHCP / Cloudflare / Google / Quad9 via `networksetup`, applied to
      whichever service currently carries the default route, with a ✓ on the one in
      use. Verified by round-trip: Google → Cloudflare → read back → restored.
- [ ] `setup.default.browser` → no supported CLI. `duti` is unmaintained and the
      replacement API is private. Needs a decision: ship the dependency or open the
      pane.
- [ ] `setup.default.terminal|editor|agent` → our own state, used by the app bindings

## P6 — install / remove  (upstream: 155 entries, mostly pacman)

- [ ] `install.package` → `brew install` with a search prompt
- [ ] `install.style.font` → `brew install --cask font-*` for the six upstream fonts
- [ ] A curated subset of browsers/services that exist as casks
- [ ] Everything AUR/pacman-only: **not ported**, documented as such

## P7 — update  (upstream: 27 entries)

- [ ] `update.omarchy` → `git pull` + `./install.sh` in this repo
- [ ] `update.config.*` → re-copy one config from the repo
- [ ] `update.timezone` / `update.time` → `systemsetup`
- [ ] `update.hardware.*` → N/A (macOS manages its own drivers)

## Not ported, and why

| Upstream | Why |
|---|---|
| `apps` provider | Raycast already is the app launcher |
| `install.aur`, most of `remove.*` | pacman/AUR have no macOS equivalent |
| `update.channel.*` | Omarchy's own release channels |
| `system.hibernate` | Apple Silicon has no hibernate |
| `style.bar.position.left/right` | sketchybar is horizontal only |
| `trigger.hardware.touchpad-haptics` | no public macOS API |
