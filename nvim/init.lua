vim.env.PATH = vim.env.HOME .. "/.local/share/mise/shims" .. ":" .. vim.env.PATH

require("config.globals")
require("config.lazy")
require("config.options")
require("config.keymaps")
