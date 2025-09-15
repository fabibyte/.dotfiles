require("full-border"):setup()
require("whoosh"):setup({})

local catppuccin_theme = require("yatline-catppuccin"):setup("macchiato")

local yatline = {
    theme = catppuccin_theme,

    section_separator = { open = "", close = "" },
    part_separator = { open = "|", close = "" },
    inverse_separator = { open = "", close = "" },

    style_a = {
        fg = "#3b4540",
        bg_mode = {
            normal = "green",
            select = "green",
            un_set = "green"
        }
    },
    style_b = { bg = "#3d4350", fg = "green" },
    style_c = { bg = "reset", fg = "#abb2bf" },
    show_background = false,

    header_line = {
        left = {
            section_a = {
                {type = "line", custom = false, name = "tabs", params = {"left"}},
            },
            section_b = {
            },
            section_c = {
            }
        },
        right = {
            section_a = {
                {type = "string", custom = false, name = "date", params = {"%A, %d %B %Y"}},
            },
            section_b = {
                {type = "string", custom = false, name = "date", params = {"%X"}},
            },
            section_c = {
            }
        }
    },

    status_line = {
        left = {
            section_a = {
                {type = "string", custom = false, name = "tab_mode"},
            },
            section_b = {
                {type = "coloreds", custom = false, name = "count"},
            },
            section_c = {
                {type = "string", custom = false, name = "hovered_size"},
            }
        },
        right = {
            section_a = {
                {type = "string", custom = false, name = "cursor_position"},
            },
            section_b = {
                {type = "string", custom = false, name = "cursor_percentage"},
            },
            section_c = {
                {type = "string", custom = false, name = "hovered_file_extension", params = {true}},
                {type = "coloreds", custom = false, name = "permissions"},
            }
        }
    },
}

require("yatline"):setup(yatline)

