return {
    "mfussenegger/nvim-lint",
    config = function()
        local lint = require("lint")

        -- configure linters by filetype
        lint.linters_by_ft = {
            rust = { "clippy" },
        }

        local function cspell()
            if vim.g.enable_cspell == true then
                lint.try_lint("cspell")
            end
        end

        local function run_all()
            -- run linter for current filetype
            lint.try_lint()
            -- run cspell if enabled
            cspell()
        end

        -- autocmd to run cspell immediately after toggling it
        -- otherwise would need to force it through opening a new buffer
        -- or saving etc.
        vim.api.nvim_create_autocmd("User", {
            pattern = "CspellToggled",
            callback = cspell,
        })

        -- autocmd to run linters
        vim.api.nvim_create_autocmd({ "VimEnter", "BufAdd", "BufWritePost" }, {
            callback = run_all,
        })
    end,
    dependencies = {
        "williamboman/mason.nvim",
        "williamboman/mason-lspconfig.nvim",
        "neovim/nvim-lspconfig",
    },
}
