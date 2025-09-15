local M = {}

function M.foldtext()
    local line = vim.fn.getline(vim.v.foldstart) .. " ..."
    local num_lines = vim.v.foldend - vim.v.foldstart + 1
    local suffix = "[" .. num_lines .. " lines]"

    local win_width = vim.api.nvim_win_get_width(0)
    local textoff = vim.fn.getwininfo(vim.fn.win_getid())[1].textoff

    local usable_width = win_width - textoff
    local padding = math.max(0, usable_width - #line - #suffix)

    return line .. string.rep(" ", padding) .. suffix
end

return M
