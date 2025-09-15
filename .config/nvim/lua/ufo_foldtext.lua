local M = {}

vim.api.nvim_set_hl(0, "FoldSuffix", { fg = "white" })

function M.foldtext(virtText, lnum, endLnum, width, truncate)
    local newVirtText = {}
    local suffix1 = " ..."
    local suffix2 = ("[%d]"):format(endLnum - lnum)
    local suffixWidth = vim.fn.strdisplaywidth(suffix1) + vim.fn.strdisplaywidth(suffix2)
    local targetWidth = width - suffixWidth

    local textWidth = 0

    for _, chunk in ipairs(virtText) do
        local chunkText = chunk[1]
        local chunkWidth = vim.fn.strdisplaywidth(chunkText)

        if targetWidth > textWidth + chunkWidth then
            table.insert(newVirtText, chunk)
        else
            chunkText = truncate(chunkText, targetWidth - textWidth)
            table.insert(newVirtText, chunk)
            break
        end
        textWidth = textWidth + chunkWidth
    end

    local suffix = suffix1 .. (' '):rep(targetWidth - textWidth) .. suffix2
    table.insert(newVirtText, { suffix, "FoldSuffix" })
    return newVirtText
end

return M
