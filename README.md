# omarchy-mac

An [Omarchy](https://github.com/basecamp/omarchy)-flavoured macOS desktop: tiling window
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
| `⌥Space` | launcher | `SUPER+SPACE` |
| `⌥⇧Space` | toggle the bar | `SUPER+SHIFT+SPACE` |
| `⌥/` `⌥⌃/` | display scale up / down | `SUPER+SLASH` |
| `⌥R` | resize mode | — |

`⌥Return` is registered by **Ghostty itself** (`keybind = global:alt+enter=new_window`),
not AeroSpace — see Notes.

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

Swap themes by lifting `colors.toml` from any
[Omarchy theme](https://github.com/basecamp/omarchy/tree/master/themes) into
`sketchybarrc`, `ghostty/config` and the plugin scripts.

## Notes and honest limitations

Things that do **not** work the way you'd expect on macOS, each verified the hard way:

- **No scrolling layout.** AeroSpace has `tiles`, `accordion`, `floating` — that's all.
  `⌥L` toggles `tiles` ⇄ `h_accordion` as the nearest analogue. Tune the peek with
  `accordion-padding` (default 80 here).
- **Brightness needs a private framework.** `brew install brightness` fails with
  `-536870201`; ioreg's `IODisplayParameters."brightness"` is pinned at exactly
  `32768/65536` (always reports 50%); `"rawBrightness"` never moves. Only
  `DisplayServicesGet/SetBrightness` works — called via ctypes, no compilation.
- **sketchybar's notch properties don't work.** `notch_width` alone does nothing, and
  adding `notch_display_height` blanks the bar entirely. Nothing is placed in the bar's
  centre as a result.
- **Popup rows need a fixed `label.width`.** sketchybar sizes a popup when its items are
  *created*; rows filled in later don't re-measure, so long labels clip.
- **Wi-Fi SSID is not shown.** macOS returns the literal string `<redacted>` from
  `ipconfig getsummary` without Location Services permission, so the item is icon-only.
- **No `ghostty +new-window` on macOS** ("not supported on this platform"), and
  `open -na Ghostty` spawns a second app instance. Hence Ghostty's own global hotkey.
- **`sketchybar --query` can't see** `background`, `drawing` on popup items, or
  `notch_width` — don't trust it to verify those.

## Layout

```
config/
  aerospace.toml              window manager + keybindings
  wezterm.lua                 WezTerm, Solitude
  ghostty/config              Ghostty, Solitude
  sketchybar/
    sketchybarrc              bar layout
    plugins/                  panel scripts
install.sh
```

Paths are stored as `__HOME__` and substituted at install time.

## Credits

[Omarchy](https://github.com/basecamp/omarchy) by Basecamp (MIT) — the design this follows,
and the source of the Solitude palette and the usage collectors.
[omachy](https://github.com/dough654/omachy) showed that Alt-as-SUPER is the right call on macOS.

MIT
