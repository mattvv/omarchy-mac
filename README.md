# omarchy-mac

An [Omarchy](https://github.com/omacom/omarchy)-flavoured macOS desktop: tiling window
management, a bar with working panels, and the **Solitude** theme across terminal, bar and
window borders.

Omarchy is DHH's Arch Linux + Hyprland setup. This is not a port of it — macOS cannot run
Hyprland. It reproduces the *feel* using native Mac equivalents, staying faithful to
Omarchy's actual config where the platform allows and documenting where it doesn't.

![theme](https://img.shields.io/badge/theme-Solitude-798186) ![platform](https://img.shields.io/badge/platform-Apple%20Silicon-101315)

## What it gives you

| Omarchy | Here |
|---|---|
| Hyprland | [AeroSpace](https://github.com/nikitabobko/AeroSpace) |
| Omarchy shell bar | [SketchyBar](https://github.com/FelixKratz/SketchyBar) |
| Hyprland borders | [JankyBorders](https://github.com/FelixKratz/JankyBorders) |
| walker launcher | Raycast on `Cmd+Space` |
| omarchy's image picker | the same carousel, rebuilt in AppKit |
| Alacritty/Ghostty | Ghostty (WezTerm config included too) |
| Solitude theme | same palette, everywhere |

## Install

```sh
git clone https://github.com/USER/omarchy-mac.git
cd omarchy-mac
./install.sh
```

Idempotent, and backs up any config it replaces to `~/.config/omarchy-mac-backup-<timestamp>`.

Three steps macOS will not let a script do — the installer prints these too:

1. **Privacy & Security → Accessibility**: enable **AeroSpace** and **Ghostty**
2. **Raycast → Settings → General → Raycast Hotkey**: press `Cmd+Space`
3. Log out and back in if Spotlight still holds `Cmd+Space`

## Keybindings

Omarchy's `SUPER` maps to **Option (⌥)**, not Command. Using ⌘ would clobber `⌘W`, `⌘T`,
`⌘F`, `⌘S`, `⌘L` and `⌘1-9` in every Mac app. Everything else stays faithful.

| Key | Action | Omarchy |
|---|---|---|
| `⌥ ←→↑↓` | focus window | `SUPER+arrows` |
| `⌥⇧ ←→↑↓` | swap window | `SUPER+SHIFT+arrows` |
| `⌥W` | close window | `SUPER+W` |
| `⌥F` | fullscreen | `SUPER+F` |
| `⌥T` | toggle float/tile | `SUPER+T` |
| `⌥J` | toggle split | `SUPER+J` |
| `⌥L` | dwindle ⇄ scrolling | `SUPER+L` |
| `⌥1-0` | switch workspace | `SUPER+1-0` |
| `⌥⇧1-0` | move window + follow | `SUPER+SHIFT+1-0` |
| `⌥⌃⇧1-0` | move window silently | `SUPER+SHIFT+ALT+1-0` |
| `⌥Tab` / `⌥⇧Tab` | next / prev workspace | `SUPER+TAB` |
| `⌥⌃Tab` | last workspace | `SUPER+CTRL+TAB` |
| `⌥Return` | new terminal window | `SUPER+RETURN` |
| `⌥⇧B` | browser | `SUPER+SHIFT+B` |
| `⌥⇧N` | editor | `SUPER+SHIFT+N` |
| `⌥⇧M` | music | `SUPER+SHIFT+M` |
| `⌥⇧F` | file manager | `SUPER+SHIFT+F` |
| `⌥⇧/` | passwords | `SUPER+SHIFT+SLASH` |
| `⌘Space` | the Omarchy menu | `SUPER+ALT+SPACE` |
| `⌥O` | the Omarchy menu | — |
| `⌥K` | keybindings reference | — |
| `⌥Space` | Raycast | `SUPER+SPACE` |
| `⌥⌃⇧Space` | theme picker | `SUPER+SHIFT+CTRL+SPACE` |
| `⌥⌃Space` | background picker | `SUPER+CTRL+SPACE` |
| `⌥⇧Space` | toggle the bar | `SUPER+SHIFT+SPACE` |
| `⌥/` `⌥⌃/` | display scale up / down | `SUPER+SLASH` |
| `⌥R` | resize mode | — |

`⌥⌃Space` is macOS's own *select next keyboard layout* shortcut and part of VoiceOver's
`VO+Space`. It only collides if you have more than one input source enabled or use
VoiceOver — clear it in System Settings → Keyboard → Shortcuts → Input Sources if so.

`⌥Return` is registered by **Ghostty itself** (`keybind = global:alt+enter=new_window`),
not AeroSpace — see Notes.

## The menu

Omarchy runs two launchers: **walker** opens apps, and **`omarchy-menu`** holds system
actions. Only the first maps to Raycast. The second is this:

```
⌘Space        Style  ›  Theme · Background · Font · Menu Bar
              Trigger › Screenshot · Screen recording · Colour picker · Stay awake
              Setup   › Configs · Displays · Keyboard · Trackpad · DNS
              Update  › Update omarchy-mac · Reinstall config · Date & Time
              Install › Fonts
              Learn   › Keybindings · Docs
              System  › Screensaver · Lock · Suspend · Logout · Reboot · Shutdown
```

Typing searches **everything** — the whole tree and every installed application — because
`⌘Space` is where you already reach for the launcher. `back` finds *Style › Background*;
`ghost` finds Ghostty. Escape clears the query, then goes up a level, then closes.

The menu is defined in `config/menu.jsonc` using upstream's schema: dotted ids imply
hierarchy, an `action` runs and anything else is a submenu, and a `checked` command puts a
tick on a row. Rows carry live state — Stay awake shows whether the assertion is up, DNS
shows which resolver is in use, Font shows which one is set.

**Only entries whose actions work on macOS are in the file.** Night Shift, Focus and the
default browser have no supported CLI, so they have no rows rather than rows that do
nothing. `dev-notes/menu-plan.md` maps all 340 of upstream's entries and says which are
not coming, and why.

### Keybindings reference

`⌥K` lists every binding read from your own `~/.aerospace.toml`, plus Ghostty's global
hotkey, with chords rendered in macOS order (`alt-ctrl-shift-space` → `⌃⌥⇧Space`) and
descriptions derived from the commands rather than a table keyed on chords, which would
rot the moment you rebind something.

It is a reference card: picking a row does **not** run the binding, which is a deliberate
divergence from upstream. Once the overlay closes, `close` would act on whatever gained
focus and `mode resize` would strand you in a mode with nothing on screen to say so.

## The bar

Layout follows Omarchy's `config/omarchy/shell.json`:

```
  1 2 3 … 10   dwindle                 display  AI  bluetooth  wifi  volume  cpu  mem  battery  clock
└──────── left ────────┘             └──────────────────────── right ────────────────────────────┘
```

Every right-hand item opens a panel on click. Panels close when the pointer leaves the bar.

| Panel | Shows |
|---|---|
| **clock** | world times — edit `clock_popup.sh` for your cities |
| **battery** | power source, time remaining |
| **cpu / memory** | top 3 processes |
| **volume** | draggable slider, mute toggle |
| **wifi** | status, IP, toggle |
| **bluetooth** | status, connected devices, toggle |
| **AI usage** | Claude + Codex rate-limit percentages and reset times |
| **display** | scale picker (`1.5×`…`2.81×`) and a brightness slider |

### AI usage

Ports the collector from Omarchy's `omarchy-agent-usage-claude` and
`omarchy-agent-usage-codex`:

- **Claude** — `api.anthropic.com/api/oauth/usage`, including the model-scoped entries in
  the `limits` array. Those matter: a scoped weekly limit is often your *highest*
  utilisation and is invisible if you only read the flat buckets.
- **Codex** — drives `codex app-server` over JSON-RPC (`account/rateLimits/read`).
- Local token counts come from `~/.claude/projects/**/*.jsonl`.

Credentials are read from the macOS **Keychain** (Omarchy reads `~/.claude/.credentials.json`,
which is Linux-only). **The token is used solely in the `Authorization` header — never
printed, logged, or cached.** Only the response is cached, for 5 minutes.

## Theme

Omarchy's **Solitude** — a desaturated near-monochrome dark palette.

| | |
|---|---|
| background | `#101315` (terminal uses `#080a0b`) |
| foreground | `#cacccc` |
| accent | `#798186` |
| borders | gradient `#798186 → #cacccc` |

It is the default, not a commitment — every other Omarchy theme is one `⌥⌃⇧Space` away.
See [Themes](#themes).

## Themes

All 22 [Omarchy themes](https://github.com/omacom/omarchy) are vendored
as palettes under `themes/`, including the light ones.

### The picker

`⌥⌃⇧Space` opens the full-screen picker — omarchy's, rebuilt for AppKit: one expanded
preview in the middle, every other theme a narrow skewed slice fanning out either side,
arrows or two-finger swipe to slide, type to filter, `⏎` to wear it, `esc` to back out.
The geometry is lifted from omarchy's `ImagePicker.qml` (768×475 preview, 108×432 slices
at −30 overlap, 28px skew), scaled to your screen.

Each card is a small mock desktop drawn from that theme's own palette — its wallpaper, its
bar, a terminal in its colours — so you are looking at the theme, not at a name in a list.
A theme whose wallpaper hasn't been downloaded yet still draws in its own colours.

`⌘B` on any theme wears it and drops straight into its backgrounds.

### Backgrounds

`⌥⌃Space` picks a background for the current theme — the same carousel, no labels and no
filter, because you are looking at pictures. Every theme keeps its own choice, so going
back to a theme restores the wallpaper you left it on.

```sh
theme.py bg next              # cycle within the current theme
theme.py bg current           # what's on screen
theme.py fetch --all          # pull every theme's backgrounds up front (~15 MB)
```

Backgrounds come from upstream on demand. A theme switch fetches one inline and the rest
in a detached process, so switching never waits on the network.

### From Cmd+Space

`install.sh` generates Raycast script commands into `~/.local/share/omarchy-mac/raycast`
(add it once: Raycast → Settings → Extensions → **+** → Add Script Directory):

| Raycast command | Does |
|---|---|
| **Omarchy Theme** | dropdown of all 22, applies on `⏎` |
| **Omarchy Theme Picker** | opens the full-screen picker |
| **Omarchy Background** | opens the background picker |
| **Omarchy Next Background** | cycles the current theme's backgrounds |

The palette icon in the bar opens the same pickers — left click themes, right click
backgrounds.

```sh
theme.py list              # names + mode
theme.py set tokyo-night   # apply
theme.py current
```

Nothing rewrites your app configs. Like Omarchy's `~/.local/state/omarchy/current/theme/`,
a switch regenerates three files that the configs *include*:

| Generated | Consumed by |
|---|---|
| `~/.config/sketchybar/theme.sh` | `sketchybarrc` and every plugin, via `source` |
| `~/.config/ghostty/theme.conf` | `config-file = ?"…"` |
| `~/.config/wezterm-theme.lua` | `dofile`, applied *after* the bar plugin |
| `~/.config/zed/themes/omarchy.json` | Zed, once you select the **Omarchy** theme |

### Zed

A theme switch regenerates a full Zed theme — 130 style keys derived from the palette's
22 colours, every one checked against Zed's own schema by the test suite.

Zed is the awkward case, because a theme is *selected* in `settings.json`, which is your
file with your comments in it. So the generated theme always carries one name, **Omarchy**.
Select it once (`⌘K ⌘T`, or set `"theme": "Omarchy"`); after that every switch only
rewrites the theme file, which Zed applies **live, with no restart**. We never touch your
settings again.

Three things about Zed's theme loading, each established by testing rather than docs:

- **The themes registry does not recurse.** A theme at `themes/<dir>/theme.json` is never
  read — Zed logs `Is a directory (os error 21)`. It has to be a flat file.
- **A *new* theme file is only discovered at startup.** Rewriting one Zed already knows
  applies immediately; adding one does not.
- **No style key is required.** Zed's schema marks all 131 optional and fills the rest from
  its default theme, so a partial theme renders rather than being rejected.

Colours are pre-blended and opaque. Zed accepts alpha, but then the result depends on what
is painted underneath — and with `background.appearance: blurred` that is not hypothetical.
Text colours are nudged toward black or white only as far as WCAG 4.5:1 requires: several
palettes have a `muted` that is fine for a bar and unreadable as a comment. The ANSI
colours are left exactly as the palette states them — those are a contract with terminal
programs, and a "corrected" red is no longer red.

A switch also sets **macOS light/dark appearance** from the theme's `mode`. This matters
more than the config files: browsers, Finder and native apps follow the system appearance,
not anything we generate. Without it a light theme leaves half the desktop dark.

## Optional: real scrolling layout

Stock AeroSpace has three layouts — `tiles`, `accordion`, `floating` — and **no scrolling
layout**, so the base setup approximates Omarchy's with a horizontal accordion. It's close
in spirit, not in mechanism.

If you want the real thing:

```sh
./bin/install-aerospace-fork.sh          # builds from source; needs Xcode
./bin/revert-aerospace-fork.sh           # back to the Homebrew build
```

This builds a fork of AeroSpace carrying [PR #2057](https://github.com/nikitabobko/AeroSpace/pull/2057)
by **vadika** (adds `scrolling` and `tabs` layouts, plus a `scroll` command), and a peek
on top so a sliver of the next page stays visible instead of the page boundary being a
hard cut.

| Key | Stock | With the fork |
|---|---|---|
| `⌥L` | dwindle ⇄ accordion | dwindle → scrolling → tabs |
| `⌥⌃←` `⌥⌃→` | — | scroll the viewport a page |

`layout_toggle.sh` detects which build you have (the `scroll` subcommand only exists in
the fork) and cycles accordingly, so the same config works either way.

Tune the sliver in `~/.aerospace.toml`, then `aerospace reload-config`:

```toml
scrolling-peek-width = 40   # points; 0 disables
```

### Things that will bite you

- **`brew upgrade` silently reverts you to stock** — the cask owns both
  `/Applications/AeroSpace.app` and the `aerospace` symlink. Worse, stock then *refuses to
  load your config*, because `scrolling-peek-width` and `scroll` are unknown to it. Re-run
  the install script, or revert first.
- **The fork-only config keys are added by the install script, not shipped in
  `config/aerospace.toml`** — for exactly that reason. Don't move them.
- **Don't `git checkout xcode/AeroSpace.xcodeproj/project.pbxproj`** after running
  `generate.sh`. The committed version hardcodes a codesign identity
  (`aerospace-codesign-certificate`) that exists on no machine but the maintainer's, and
  the Xcode build then fails while a following CLI build still returns 0 — so the whole
  thing looks successful and you install a stale app.
- **You can't jump from `tabs` straight to `scrolling`.** `layout scrolling` only applies
  when the focused node is the root container. The `⌥L` cycle routes through `tiles`, but
  a direct `aerospace layout scrolling` from tabs fails silently.
- **Multi-monitor**: the peek auto-suppresses when a display sits to the right, because a
  window manager can't clip windows and the peeking window would bleed onto it. Built-in
  alone → peek works. Docked with an external on the right → peek turns off.
- It's an unmerged PR. You're off upstream releases until it lands.

## Notes and honest limitations

Things that do **not** work the way you'd expect on macOS, each verified the hard way:

- **No scrolling layout in stock AeroSpace.** It has `tiles`, `accordion`, `floating` —
  that's all, so `⌥L` toggles `tiles` ⇄ `h_accordion` as the nearest analogue (tune it with
  `accordion-padding`, default 80 here). See *Optional: real scrolling layout* above for
  the fork that adds a genuine one.
- **Brightness needs a private framework.** `brew install brightness` fails with
  `-536870201`; ioreg's `IODisplayParameters."brightness"` is pinned at exactly
  `32768/65536` (always reports 50%); `"rawBrightness"` never moves. Only
  `DisplayServicesGet/SetBrightness` works — called via ctypes, no compilation.
- **Use sketchybar's `q`/`e` positions for the notch, not `notch_width`.** `q` places an
  item immediately left of the notch and `e` immediately right — both are legal positions
  (a bogus one errors with `Illegal position`). The `notch_width` property does nothing on
  its own, and adding `notch_display_height` blanks the bar entirely. Nothing sits in the
  bar's `center`.
- **Popup rows need a fixed `label.width`.** sketchybar sizes a popup when its items are
  *created*; rows filled in later don't re-measure, so long labels clip.
- **Wi-Fi SSID is not shown.** macOS returns the literal string `<redacted>` from
  `ipconfig getsummary` without Location Services permission, so the item is icon-only.
- **No `ghostty +new-window` on macOS** ("not supported on this platform"), and
  `open -na Ghostty` spawns a second app instance. Hence Ghostty's own global hotkey.
- **Reload sketchybar, never kill-and-respawn it.** `pkill` + relaunch races its lock
  file: the replacement bails with `could not acquire lock-file` and the old instance
  survives, leaving the bar a theme behind. `sketchybar --reload` re-executes the config
  in place.
- **Terminals read config at startup.** A theme switch does not repaint open windows.
  WezTerm watches its main config (but not `dofile`d files, so the main file is touched);
  Ghostty has no reload CLI and binds `reload_config` to `⌘⇧,`, driven via System Events —
  which needs an Automation grant and so may no-op when triggered from a bar click.
- **Quickshell does not run here.** Omarchy's picker is a Quickshell/QML plugin, and
  Quickshell is Linux/BSD only — its overlay is a wlroots layer-shell surface
  (`WlrLayershell`, `WlrKeyboardFocus.Exclusive`), a Wayland protocol macOS has no
  equivalent of. The picker here is the same *design* in ~580 lines of AppKit, not a port.
- **Upstream moved.** `basecamp/omarchy` is now `omacom/omarchy` and its default branch is
  no longer `master`, so old `raw.githubusercontent.com` paths 404. Backgrounds are fetched
  through the contents API, which redirects by repository id. Most of them are `.webp` now.
- **The bar floats above the picker.** sketchybar sits at a higher window level than the
  picker's overlay panel, so the top strip stays lit while everything else dims. Omarchy's
  layer-shell overlay covers its bar; matching that would mean shielding-window level.
- **`sketchybar --query` can't see** `background`, `drawing` on popup items, or
  `notch_width` — don't trust it to verify those.

## Layout

```
bin/
  omarchy-picker.swift        the full-screen carousel (built into a .app)
  theme.py                    palettes, backgrounds, picker rows, Raycast commands
  theme_menu.sh               ⌥⌃⇧Space — pick a theme
  bg_menu.sh                  ⌥⌃Space  — pick a background
config/
  aerospace.toml              window manager + keybindings
  wezterm.lua                 WezTerm, Solitude
  ghostty/config              Ghostty, Solitude
  sketchybar/
    sketchybarrc              bar layout
    plugins/                  panel scripts
themes/                       22 vendored Omarchy palettes
install.sh
```

Paths are stored as `__HOME__` and substituted at install time.

## Credits

[Omarchy](https://github.com/omacom/omarchy) (MIT) — the design this follows, and the
source of the palettes, the backgrounds and the usage collectors. The picker's geometry is
taken from its `shell/plugins/image-picker/ImagePicker.qml` down to the numbers.
[omachy](https://github.com/dough654/omachy) showed that Alt-as-SUPER is the right call on macOS.

MIT
