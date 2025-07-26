return {
    {
        "vague2k/vague.nvim",
        priority = 1000,
        config = function()
            require("vague").setup({
                transparent = true,
            })
        end,
    },
    { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
}
