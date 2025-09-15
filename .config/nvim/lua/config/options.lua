vim.opt.cursorline = true
vim.opt.colorcolumn = "80"

vim.opt.number = true
vim.opt.relativenumber = true

vim.opt.expandtab = true
vim.opt.shiftwidth = 4

vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.opt.wrap = false

vim.opt.foldenable = true
vim.opt.foldminlines = 3
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
-- vim.opt.foldmethod = "expr"
-- vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
-- vim.opt.foldtext = "v:lua.require('foldtext').foldtext()"

vim.opt.signcolumn = "yes:1"
vim.opt.statuscolumn = "%!v:lua.require('statuscolumn').statuscolumn()"
vim.cmd.colorscheme "catppuccin-macchiato"
vim.opt.winborder = "rounded"
