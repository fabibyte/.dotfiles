return {
    "stevearc/conform.nvim",
    opts = {
        formatters_by_ft = {
            rust = { "rustfmt" },
            cs = { lsp_format = "prefer" },
            c = { "clang-format" },
            cpp = { "clang-format" },
            gradle = { "npm-groovy-lint" },
            java = { "google-java-format" },
            lua = { "stylua" },
            xml = { "prettier" },
            typescript = { "prettier" },
            typescriptreact = { "prettier" },
            javascriptreact = { "prettier" },
            javascript = { "prettier" },
            html = { "prettier" },
            css = { "prettier" },
            python = { "black" },
            json = { "prettier" },
        },
    },
}
