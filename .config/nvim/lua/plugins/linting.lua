return {
    "mfussenegger/nvim-lint",
    config = function()
        require("lint").linters_by_ft = {
            rust = { "clippy" },
        }

        local function lint_by_ft()
            require("lint").try_lint()
        end

        local function cspell()
            if vim.g.enable_cspell == true then
                require("lint").try_lint("cspell")
            end
        end

        vim.api.nvim_create_autocmd("User", {
            pattern = "CspellToggled",
            callback = cspell,
        })
        vim.api.nvim_create_autocmd({ "VimEnter", "BufAdd", "BufWritePost" }, {
            callback = function()
                lint_by_ft()
                cspell()
            end,
        })
    end,
    dependencies = {
        "williamboman/mason.nvim",
        "williamboman/mason-lspconfig.nvim",
        "neovim/nvim-lspconfig",
    },
}
