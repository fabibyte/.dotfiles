return {
    {
        'nvim-lualine/lualine.nvim',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        opts = {
            options = {
                theme = "dracula",
                section_separators = { left = '', right = ''},
                component_separators = { left = '|', right = '|'},
            },
            sections = {
                lualine_x = {'encoding', 'filetype'},
            },
        }
    }
}
