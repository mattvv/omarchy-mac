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
- [x] Keybinding ⌥O (⌥⌘Space is macOS "Show Finder search window"). Note it takes ⌥O
      away from typing `ø` on a US layout.
- [ ] Bar: leftmost item opens the menu, like omarchy's

## P1 — style  (upstream: 20 entries)

- [ ] `style.theme` → existing theme picker, moved under the menu
- [ ] `style.background` → existing background picker
- [ ] `style.font` → pick a terminal font, write to Ghostty + WezTerm theme files
- [ ] `style.bar.position` → sketchybar `position=top|bottom`; left/right N/A (sketchybar
      is horizontal only — say so rather than faking it)
- [ ] `style.bar.transparency` → bar colour alpha
- [ ] `style.about` / `style.screensaver` → macOS screen saver module + text

## P2 — system  (upstream: 7 entries, all map)

- [ ] `system.lock` → `pmset displaysleepnow` / CGSession suspend
- [ ] `system.suspend` → `pmset sleepnow`
- [ ] `system.logout` / `reboot` / `shutdown` → osascript System Events
- [ ] `system.screensaver` → open ScreenSaverEngine
- [ ] `system.hibernate` → N/A on Apple Silicon; omit with a note

## P3 — learn  (upstream: 9 entries) — includes the keybindings app

- [ ] **Keybindings viewer**: parse `~/.aerospace.toml` `[mode.*.binding]`, plus Ghostty's
      `keybind = global:` lines and our own menu bindings; show in the list overlay,
      searchable; picking one runs it. Upstream reads `hyprctl binds`; our source of truth
      is the TOML, so it stays correct when the config changes.
- [ ] Doc links: Omarchy, AeroSpace (in place of Hyprland), macOS, Neovim, Bash, Tmux

## P4 — trigger  (upstream: 46 entries)

- [ ] `trigger.capture.screenshot` → `screencapture -i`
- [ ] `trigger.capture.screenrecord` (+ audio variants) → `screencapture -v`
- [ ] `trigger.capture.color` → DigitalColor Meter / a small picker
- [ ] `trigger.capture.text` → macOS Live Text OCR via Vision framework
- [ ] `trigger.emoji` → macOS emoji palette (`⌃⌘Space`)
- [ ] `trigger.toggle.idle-lock` → `caffeinate` on/off
- [ ] `trigger.toggle.nightlight` → Night Shift
- [ ] `trigger.toggle.notifications` → Do Not Disturb / Focus
- [ ] `trigger.toggle.top-bar` → existing `sketchybar --bar hidden=toggle`
- [ ] `trigger.share.*` → AirDrop / `shortcuts` share sheet
- [ ] `trigger.hardware.mirror-display` → `displayplacer` (already a dependency)

## P5 — setup  (upstream: 66 entries)

- [ ] `setup.monitors` → `displayplacer` arrangement
- [ ] `setup.keybindings` → open `~/.aerospace.toml` in the editor
- [ ] `setup.input` → key repeat, trackpad speed via `defaults`
- [ ] `setup.network.dns` → `networksetup -setdnsservers` (DHCP/Cloudflare/Google/custom)
- [ ] `setup.default.browser` → `duti` or the modern `open -a` default-handler API
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
