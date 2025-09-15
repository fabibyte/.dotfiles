-- general
vim.keymap.set("n", "<leader>bd", ":bdelete<CR>")
vim.keymap.set("n", "<leader>bp", ":bprevious<CR>")
vim.keymap.set("n", "<leader>bn", ":bnext<CR>")
vim.keymap.set("n", "<leader>a", ":e#<CR>")
vim.keymap.set("n", "<leader>hls", ":nohlsearch<CR>")
vim.keymap.set("n", "<leader>w", ":w<CR>")
vim.keymap.set("n", "<leader>ww", ":wq<CR>")
vim.keymap.set("n", "<leader>l", function()
    vim.g.enable_cspell = not vim.g.enable_cspell
    vim.api.nvim_exec_autocmds("User", { pattern = "CspellToggled" })
end)

vim.keymap.set({ "n", "v" }, "<leader>y", '"+y')
vim.keymap.set({ "n", "v" }, "<leader>p", '"+p')

-- code
vim.keymap.set("n", "<leader>d", vim.lsp.buf.definition)
vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename)
vim.keymap.set("n", "<leader>a", vim.lsp.buf.code_action)
vim.keymap.set("n", "<leader>f", function()
    require("conform").format({ async = true })
end)

-- folds
vim.keymap.set("n", "<leader>fo", "zo")
vim.keymap.set("n", "<leader>fc", "zc")
vim.keymap.set("n", "<leader>foa", require("ufo").openAllFolds)
vim.keymap.set("n", "<leader>fca", require("ufo").closeAllFolds)

-- window
vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")
vim.keymap.set("n", "<C-q>", "<C-w>c")

-- telescope
local builtin = require("telescope.builtin")

vim.keymap.set("n", "<leader>tf", builtin.find_files, { desc = "Telescope find files" })
vim.keymap.set("n", "<leader>tg", builtin.live_grep, { desc = "Telescope live grep" })
vim.keymap.set("n", "<leader>tb", builtin.buffers, { desc = "Telescope buffers" })

-- harpoon
local harpoon = require("harpoon")

vim.keymap.set("n", "<leader>ha", function()
    harpoon:list():add()
end)
vim.keymap.set("n", "<leader>hr", function()
    harpoon:list():remove()
end)
vim.keymap.set("n", "<leader>hv", function()
    harpoon.ui:toggle_quick_menu(harpoon:list())
end)

vim.keymap.set("n", "<leader>h1", function()
    harpoon:list():select(1)
end)
vim.keymap.set("n", "<leader>h2", function()
    harpoon:list():select(2)
end)
vim.keymap.set("n", "<leader>h3", function()
    harpoon:list():select(3)
end)
vim.keymap.set("n", "<leader>h4", function()
    harpoon:list():select(4)
end)

vim.keymap.set("n", "<leader>hp", function()
    harpoon:list():prev()
end)
vim.keymap.set("n", "<leader>hn", function()
    harpoon:list():next()
end)
