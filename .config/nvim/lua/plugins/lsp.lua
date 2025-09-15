return {
    {
        "williamboman/mason.nvim",
        opts = {},
    },
    {
        "williamboman/mason-lspconfig.nvim",
        dependencies = {
            "williamboman/mason.nvim",
        },
        opts = {
            ensure_installed = vim.g.language_servers
        }
    },
    {
        "neovim/nvim-lspconfig",
        lazy = false,
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "saghen/blink.cmp",
        },
        config = function()
            local capabilities = require('blink.cmp').get_lsp_capabilities()

            for _, server in ipairs(vim.g.language_servers) do
                vim.lsp.config(server, { capabilities = capabilities } )
            end
        end
    },
    {
        url = "https://gitlab.com/schrieveslaach/sonarlint.nvim.git",
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "neovim/nvim-lspconfig",
        },
        config = function ()
            require('sonarlint').setup({
                server = {
                    cmd = {
                        'sonarlint-language-server',
                        '-stdio',
                        '-analyzers',
                        vim.fn.expand("$MASON/share/sonarlint-analyzers/sonarpython.jar"),
                        vim.fn.expand("$MASON/share/sonarlint-analyzers/sonarcfamily.jar"),
                        vim.fn.expand("$MASON/share/sonarlint-analyzers/sonarjava.jar"),
                        vim.fn.expand("$MASON/share/sonarlint-analyzers/sonarcsharp.jar"),
                        vim.fn.expand("$MASON/share/sonarlint-analyzers/sonarhtml.jar"),
                        vim.fn.expand("$MASON/share/sonarlint-analyzers/sonarjs.jar"),
                    }
                },
                filetypes = {
                    'python',
                    'cpp',
                    'c',
                    'java',
                    'cs',
                    'html',
                    'css',
                    'js',
                    'ts',
                    'jsx',
                    'tsx',
                }
            })
        end
    }
}
