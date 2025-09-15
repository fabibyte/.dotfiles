return {
    {
        "nvim-treesitter/nvim-treesitter",
        lazy = false,
        branch = "main",
        build = ":TSUpdate",
        config = function()
            require("nvim-treesitter").install({ "all" })

            vim.api.nvim_create_autocmd("FileType", {
                pattern = "*",
                callback = function()
                    pcall(vim.treesitter.start)
                end,
            })
        end,
    },
}
