return {
    "saghen/blink.cmp",
    dependencies = "rafamadriz/friendly-snippets",
    version = "*",
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
        completion = {
            menu = {
                auto_show = function(ctx)
                    return ctx.mode ~= "cmdline" or vim.g.cmdline_completion == true
                end,
            },
            documentation = {
                auto_show = true,
                window = {
                    direction_priority = {
                        menu_north = { "e", "n", "w", "s" },
                        menu_south = { "e", "s", "w", "n" },
                    },
                },
            },
        },
        keymap = {
            preset = "none",
            ["<C-y>"] = { "select_and_accept", "fallback" },
            ["<C-p>"] = { "select_prev", "fallback" },
            ["<C-n>"] = { "select_next", "fallback" },
            ["<C-b>"] = { "scroll_documentation_up", "fallback" },
            ["<C-f>"] = { "scroll_documentation_down", "fallback" },
            ["<C-c>"] = { "show", "hide" },
            ["<C-d>"] = { "show_documentation", "hide_documentation", "fallback" },
            ["<Tab>"] = { "snippet_forward", "fallback" },
            ["<S-Tab>"] = { "snippet_backward", "fallback" },
        },
        cmdline = {
            keymap = {
                preset = "none",
                ["<C-y>"] = { "select_and_accept", "fallback" },
                ["<C-p>"] = { "select_prev", "fallback" },
                ["<C-n>"] = { "select_next", "fallback" },
                ["<C-b>"] = { "scroll_documentation_up", "fallback" },
                ["<C-f>"] = { "scroll_documentation_down", "fallback" },
                ["<C-c>"] = {
                    function()
                        vim.g.cmdline_completion = not vim.g.cmdline_completion
                        return false
                    end,
                    "show",
                    "hide",
                },
                ["<C-d>"] = { "show_documentation", "hide_documentation", "fallback" },
                ["<Tab>"] = { "snippet_forward", "fallback" },
                ["<S-Tab>"] = { "snippet_backward", "fallback" },
            }
        },
        appearance = {
            use_nvim_cmp_as_default = true,
            nerd_font_variant = "mono",
        },
        sources = {
            default = { "lazydev", "lsp", "path", "snippets", "buffer" },
            providers = {
                lazydev = {
                    name = "LazyDev",
                    module = "lazydev.integrations.blink",
                    score_offset = 100,
                },
            },
        },
        signature = { enabled = true },
    },
    opts_extend = { "sources.default" },
}
