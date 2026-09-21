#!/usr/bin/env python3
"""Generate a Zed theme from an Omarchy palette.

Same rule as the rest of the switcher: never rewrite an app's config, write a
file it reads. Zed is the awkward case -- a theme is *selected* in
settings.json, which is the user's file and full of their own comments. So the
generated theme always carries one name, "Omarchy", the user selects it once,
and every switch after that only rewrites this file. settings.json is never
touched.

Three things established by testing against Zed 1.20.2 on this machine:

  * The themes registry does not recurse. A theme in
    ~/.config/zed/themes/<dir>/theme.json is never read, and the log says
    `Is a directory (os error 21)`. It has to be a flat file.
  * A theme file added while Zed is running is not discovered until restart --
    but rewriting a file Zed already knows *does* apply live, with no restart
    and no nudge. That is what makes one stable name workable.
  * No style key is required. Zed's schema marks all 131 optional and fills
    the rest from its default theme, so a partial theme renders correctly
    rather than being rejected.
"""
from __future__ import annotations
import json, os, re, tempfile
from pathlib import Path

HOME = Path.home()
ZED_THEME = HOME / ".config/zed/themes/omarchy.json"
ZED_SCHEMA = "https://zed.dev/schema/themes/v0.1.0.json"


# ── Colour maths ─────────────────────────────────────────────────────────────
#
# Opaque throughout. Zed accepts alpha, but then the result depends on whatever
# is painted underneath -- and this user has `background.appearance: blurred`
# set, where that is not a hypothetical. Every derived colour is blended here
# instead, so what is written is what is shown.

def color(v) -> str:
    if not isinstance(v, str):
        raise ValueError("expected a colour string")
    v = v.strip()
    if not re.match(r"^#?[0-9a-fA-F]{6}$", v):
        raise ValueError("invalid palette colour: %r" % (v,))
    return "#" + v.lstrip("#").lower()


def rgb(v: str):
    v = color(v)
    return tuple(int(v[i:i + 2], 16) for i in (1, 3, 5))


def blend(fg: str, bg: str, t: float) -> str:
    """Opaque blend in gamma-encoded sRGB; t is fg's share."""
    if not 0.0 <= t <= 1.0:
        raise ValueError("blend weight out of range")
    a, b = rgb(fg), rgb(bg)
    return "#%02x%02x%02x" % tuple(
        int(t * x + (1.0 - t) * y + 0.5) for x, y in zip(a, b))


def shade(bg: str, mode: str, t: float) -> str:
    """Lift a dark background toward white, darken a light one toward black."""
    if mode not in ("dark", "light"):
        raise ValueError("invalid appearance: %r" % (mode,))
    return blend("#ffffff" if mode == "dark" else "#000000", bg, t)


def luminance(v: str) -> float:
    def linear(channel):
        x = channel / 255.0
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    r, g, b = [linear(x) for x in rgb(v)]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: str, b: str) -> float:
    x, y = sorted((luminance(a), luminance(b)))
    return (y + 0.05) / (x + 0.05)


def readable(fg: str, bg: str, minimum: float = 4.5) -> str:
    """Move a colour toward black or white only as far as legibility needs.

    Several Omarchy palettes have a `muted` that is near-invisible on their own
    background -- fine for a bar, not for comments you have to read. Applied to
    text, never to the ANSI colours: those are a contract with terminal
    programs, and 'corrected' red is no longer red.
    """
    fg = color(fg)
    if contrast(fg, bg) >= minimum:
        return fg
    target = max(("#000000", "#ffffff"), key=lambda candidate: contrast(candidate, bg))
    if contrast(target, bg) < minimum:
        return target
    lo, hi = 0.0, 1.0
    for _ in range(24):
        mid = (lo + hi) / 2.0
        if contrast(blend(target, fg, mid), bg) >= minimum:
            hi = mid
        else:
            lo = mid
    return blend(target, fg, hi)


# ── The theme ────────────────────────────────────────────────────────────────

NEEDED = """
    background dark_background darker_background lighter_background
    foreground light_foreground bright_foreground muted selection accent
    red green yellow blue magenta cyan
    bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan
""".split()


def build(c: dict) -> dict:
    mode = c.get("mode", "dark")
    if mode not in ("dark", "light"):
        raise ValueError("invalid palette mode: %r" % (mode,))
    p = {k: color(c[k]) for k in NEEDED}

    bg = p["background"]
    chrome = p["dark_background"]
    elevated = p["lighter_background"]
    term_bg = p["darker_background"]
    accent = p["accent"]
    selection = p["selection"]
    fg = readable(p["foreground"], bg)
    muted = readable(p["muted"], bg)
    punctuation = readable(blend(fg, bg, 0.65), bg)
    hover = shade(bg, mode, 0.06)
    active = shade(bg, mode, 0.10)
    edge = blend(fg, bg, 0.20)
    faint = blend(fg, bg, 0.12)

    style = {}

    def put(value, keys):
        for key in keys.split():
            style[key] = value

    put(bg, "background tab.active_background editor.background editor.gutter.background")
    put(chrome, """panel.background title_bar.background status_bar.background
                   toolbar.background tab_bar.background tab.inactive_background
                   editor.subheader.background element.disabled""")
    put(elevated, "surface.background elevated_surface.background element.background")
    put(fg, "text icon editor.foreground editor.active_line_number")
    put(muted, """text.muted text.placeholder text.disabled
                  icon.muted icon.placeholder icon.disabled editor.line_number""")
    put(readable(accent, bg), "text.accent icon.accent link_text.hover")

    put(edge, "border scrollbar.thumb.border")
    put(faint, "border.variant border.disabled scrollbar.track.border")
    put(accent, "border.focused border.selected panel.focused_border")
    put("transparent", """border.transparent scrollbar.track.background
                          ghost_element.background ghost_element.disabled""")

    put(hover, "element.hover ghost_element.hover editor.active_line.background")
    put(active, "element.active ghost_element.active")
    put(selection, "element.selected ghost_element.selected")
    put(blend(accent, bg, 0.18), "drop_target.background")

    # The schema spells this one with an underscore while every sibling uses a
    # dot. Themes that follow the pattern instead of the schema get a silently
    # default scrollbar -- the installed Rosé Pine theme has exactly that bug.
    put(blend(fg, bg, 0.25), "scrollbar_thumb.background editor.invisible")
    put(blend(fg, bg, 0.40), "scrollbar.thumb.hover_background")
    put(blend(fg, bg, 0.14), "editor.wrap_guide")
    put(blend(fg, bg, 0.28), "editor.active_wrap_guide")
    put(blend(accent, bg, 0.12), "editor.highlighted_line.background")
    put(blend(accent, bg, 0.18), "editor.document_highlight.read_background")
    put(blend(accent, bg, 0.26), "editor.document_highlight.write_background")
    put(blend(p["yellow"], bg, 0.28), "search.match_background")

    style["players"] = [{"cursor": accent, "background": accent, "selection": selection}]

    # A list rather than a dict keyed on colour: the near-monochrome palettes
    # (vantablack, white) give several roles the same value.
    groups = [
        (p["magenta"], "keyword boolean constant preproc tag variant emphasis"),
        (p["green"], "string text.literal"),
        (muted, "comment comment.doc predictive"),
        (p["blue"], "function constructor link_text title"),
        (p["cyan"], """type enum hint label link_uri string.escape
                       string.special string.special.symbol"""),
        (p["yellow"], "number attribute string.regex"),
        (fg, "variable property embedded primary"),
        (accent, "operator variable.special punctuation.special emphasis.strong"),
        (punctuation, """punctuation punctuation.bracket punctuation.delimiter
                         punctuation.list_marker"""),
    ]
    syntax = {}
    for value, tokens in groups:
        for token in tokens.split():
            syntax[token] = {"color": readable(value, bg)}
    for token in ("comment", "emphasis"):
        syntax[token]["font_style"] = "italic"
    for token in ("emphasis.strong", "title", "punctuation.list_marker"):
        syntax[token]["font_weight"] = 700
    style["syntax"] = syntax

    statuses = {
        "error": "bright_red", "warning": "yellow", "info": "blue",
        "success": "green", "hint": "cyan", "created": "green",
        "modified": "yellow", "deleted": "bright_red", "conflict": "magenta",
        "ignored": "muted", "renamed": "cyan", "hidden": "muted",
        "predictive": "muted", "unreachable": "muted",
    }
    for status, source in statuses.items():
        value = p[source] if source in p else muted
        style[status] = readable(value, bg)
        style[status + ".background"] = blend(value, bg, 0.12)
        style[status + ".border"] = value

    style["terminal.background"] = term_bg
    style["terminal.foreground"] = p["foreground"]
    style["terminal.bright_foreground"] = p["bright_foreground"]
    style["terminal.dim_foreground"] = blend(p["foreground"], term_bg, 0.66)

    normal = [p["dark_background"], p["red"], p["green"], p["yellow"],
              p["blue"], p["magenta"], p["cyan"], p["foreground"]]
    bright = [p["muted"], p["bright_red"], p["bright_green"], p["bright_yellow"],
              p["bright_blue"], p["bright_magenta"], p["bright_cyan"],
              p["light_foreground"]]
    for key, base, high in zip("black red green yellow blue magenta cyan white".split(),
                               normal, bright):
        style["terminal.ansi." + key] = base
        style["terminal.ansi.bright_" + key] = high
        style["terminal.ansi.dim_" + key] = blend(base, term_bg, 0.66)

    return {
        "$schema": ZED_SCHEMA,
        "name": "Omarchy",
        "author": "omarchy-mac",
        "themes": [{"name": "Omarchy", "appearance": mode, "style": style}],
    }


def write(c: dict) -> Path:
    """Publish atomically: Zed watches this file, and a half-written theme is a
    theme it will reject."""
    ZED_THEME.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(build(c), ensure_ascii=False, indent=2) + "\n"
    handle, tmp = tempfile.mkstemp(dir=str(ZED_THEME.parent), prefix=".omarchy-", suffix=".json")
    try:
        with os.fdopen(handle, "w") as out:
            out.write(text)
        os.replace(tmp, str(ZED_THEME))
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return ZED_THEME


if __name__ == "__main__":
    print(ZED_THEME)
