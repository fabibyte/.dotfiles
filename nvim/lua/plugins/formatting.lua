return {
    "stevearc/conform.nvim",
    opts = {
        formatters_by_ft = {
            rust = { "rustfmt" },
            cs = { lsp_format = "prefer" },
            c = { "clang-format" },
            cpp = { "clang-format" },
            gleam = { "gleam" },
            go = { "gofmt" },
            gradle = { "npm-groovy-lint" },
            java = { "google-java-format" },
            lua = { "stylua" },
            xml = { "prettier" },
            ts = { "prettier" },
            html = { "prettier" },
            css = { "prettier" },
            python = { "black" },
            zig = { "zigfmt" },
            nix = { "nixfmt" },
        },
    },
}
