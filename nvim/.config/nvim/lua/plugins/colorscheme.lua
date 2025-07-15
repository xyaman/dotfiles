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
    {
        "projekt0n/github-nvim-theme",
        name = "github-theme",
        opts = {
            specs = {
                github_dark_default = {
                    bg0 = "#1d1d2b",
                    bg1 = "#151b23",
                },
            },
        },
    },
}
