return {
    "Yazeed1s/oh-lucy.nvim",
    {
        "vague2k/vague.nvim",
        priority = 1000,
        config = function()
            require("vague").setup({
                transparent = true,
            })

            vim.cmd("colorscheme vague")
        end,
    },
    { "echasnovski/mini.base16", version = false },
}
