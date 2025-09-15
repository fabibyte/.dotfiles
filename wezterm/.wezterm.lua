local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.color_scheme = 'Catppuccin Macchiato'
config.enable_tab_bar = false
config.window_decorations = "RESIZE"
config.window_close_confirmation = 'NeverPrompt'
config.audible_bell = "Disabled"

config.ssh_domains = {
  {
    name = 'wsl',
    remote_address = 'wezterm',
    multiplexing = "None",
    assume_shell = 'Posix',
    default_prog = { "fish", "-c", "clear; exec fish" }
  },
}
config.default_domain = "wsl"

return config
