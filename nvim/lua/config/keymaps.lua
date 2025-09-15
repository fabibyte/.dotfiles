-- general
vim.keymap.set("n", "<leader>bd", ":bdelete<CR>")
vim.keymap.set("n", "<leader>bp", ":bprevious<CR>")
vim.keymap.set("n", "<leader>bn", ":bnext<CR>")
vim.keymap.set("n", "<leader>a", ":e#<CR>")
vim.keymap.set("n", "<leader>hls", ":nohlsearch<CR>")
vim.keymap.set({"n", "v"}, "<M-d>", '"_d')
vim.keymap.set("n", "<M-d><M-d>", '"_dd')

vim.keymap.set("n", "<leader>cs", function()
    vim.g.enable_cspell = not vim.g.enable_cspell
    vim.api.nvim_exec_autocmds("User", { pattern = "CspellToggled" })
end)

vim.keymap.set("n", "<leader>co", function()
    vim.g.enable_completions = not vim.g.enable_completions
end)

-- yanking and pasting from windows
vim.keymap.set({ "n", "v" }, "<leader>y", '"+y')
vim.keymap.set({ "n", "v" }, "<leader>p", '"+p')

-- code
vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action)
vim.keymap.set("n", "<leader>i", vim.lsp.buf.implementation)
vim.keymap.set("n", "<leader>n", vim.lsp.buf.rename)
vim.keymap.set("n", "<leader>r", vim.lsp.buf.references)
vim.keymap.set("n", "<leader>t", vim.lsp.buf.type_definition)
vim.keymap.set("n", "<leader>d", vim.lsp.buf.definition)

local conform = require("conform")
vim.keymap.set("n", "<leader>fo", function()
    conform.format({ async = true })
end)

-- window
vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")
vim.keymap.set("n", "<C-q>", "<C-w>c")

-- fzf-lua
local fzf = require("fzf-lua")
vim.keymap.set("n", "<leader>fg", fzf.global)
vim.keymap.set("n", "<leader>ff", fzf.files)
vim.keymap.set("n", "<leader>fb", fzf.buffers)
vim.keymap.set("n", "<leader>fdd", fzf.diagnostics_document)
vim.keymap.set("n", "<leader>fdw", fzf.diagnostics_workspace)
