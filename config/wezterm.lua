-- Pull in the wezterm API
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.font_size = 16
config.window_background_opacity = 0.9
config.window_decorations = 'RESIZE'

-- bar.wezterm REPLACES config.colors wholesale (see its init.lua:74,
-- `c.colors = utilities._merge(default_colors, scheme)`), so it must be
-- applied BEFORE the palette or it silently discards it.
local bar = wezterm.plugin.require("https://github.com/adriankarlen/bar.wezterm")
bar.apply_to_config(config)

-- Omarchy "Solitude" — set after the plugin, field by field so the plugin's
-- tab_bar styling survives.
config.colors = config.colors or {}
config.colors.foreground    = '#cacccc'
config.colors.background    = '#080a0b'
config.colors.cursor_bg     = '#798186'
config.colors.cursor_border = '#798186'
config.colors.cursor_fg     = '#101315'
config.colors.selection_bg  = '#343d41'
config.colors.selection_fg  = '#cacccc'
-- black, red, green, yellow, blue, magenta, cyan, white
config.colors.ansi = {
  '#0c0e10', '#565d60', '#9fa5a9', '#d9dbdc',
  '#798186', '#aeaeae', '#707070', '#cacccc',
}
config.colors.brights = {
  '#4b4e55', '#de6145', '#343d41', '#c9c2b4',
  '#5d6367', '#9a9a9a', '#707070', '#cbc2be',
}

return config
