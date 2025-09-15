return {
    "saghen/blink.cmp",
    dependencies = { "rafamadriz/friendly-snippets" },
    version = "1.*",
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
        enabled = function()
            return vim.g.enable_completions
        end,
        completion = {
            documentation = { auto_show = true },
            accept = {
                auto_brackets = { enabled = false },
            },
        },
        signature = { enabled = true },
        cmdline = {
            completion = {
                menu = {
                    auto_show = function()
                        return vim.g.enable_completions
                    end,
                },
            },
        },
    },
}
