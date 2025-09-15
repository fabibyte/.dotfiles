local foldcolumn_cache = {}

local function foldcolumn()
    local lnum = vim.v.lnum
    local value = foldcolumn_cache[lnum]

    if value == nil then
        local foldlevel_str = tostring(vim.treesitter.foldexpr(lnum))
        local foldlevel_after_str = tostring(vim.treesitter.foldexpr(lnum + 1))
        local foldlevel_num = tonumber(foldlevel_str:match("%d+")) or -1
        local foldlevel_after_num = tonumber(foldlevel_after_str:match("%d+")) or -1

        if foldlevel_str == "0" then
            value = "%#FoldColumn#  "
        elseif foldlevel_str:match(">%d*") then
            local foldclosed = vim.fn.foldclosed(lnum)
            value = foldclosed ~= -1 and "%#FoldColumn# " or "%#FoldColumn# "
        elseif foldlevel_after_num < foldlevel_num or (foldlevel_after_str:match(">%d*") and foldlevel_num == foldlevel_after_num) then
            value = "%#FoldColumn# ╰"
        else
            value = string.format("%%#FoldColumn#%2s", foldlevel_num)
        end

        foldcolumn_cache[lnum] = value
    end

    return value
end

local function numbercolumn()
    local width = math.max(3, math.floor(math.log10(math.max(vim.fn.line('$'), 1))) + 1)

    if vim.v.relnum == 0 then
        return string.format("%%#CursorLineNr#%" .. (width - 1) .. "s ", vim.v.lnum)
    else
        return string.format("%%#LineNr#%" .. width .. "s", vim.v.relnum)
    end
end

vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
    callback = function ()
        foldcolumn_cache = {}
    end
})

local M = {}

function M.statuscolumn()
    return table.concat({
        "%s",
        numbercolumn(),
        "%#Normal# ",
        foldcolumn(),
    })
end

return M
