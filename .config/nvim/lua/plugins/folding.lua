return {
    "kevinhwang91/nvim-ufo",
    opts = {
        fold_virt_text_handler = require("ufo_foldtext").foldtext,
        provider_selector = function()
            return {'treesitter', 'indent'}
        end
    },
    dependencies = {
        "kevinhwang91/promise-async"
    }
}
