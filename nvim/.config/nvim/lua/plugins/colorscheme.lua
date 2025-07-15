return {
    "Yazeed1s/oh-lucy.nvim",
    {
        "vague2k/vague.nvim",
        priority = 1000,
        config = function()
            require("vague").setup({
                transparent = true,
            })
        end,
    },
    {
        "projekt0n/github-nvim-theme",
        name = "github-theme",
        opts = { specs = { all = { bg1 = "#151b23" } } },
    },
}
