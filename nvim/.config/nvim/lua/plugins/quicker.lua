return {
    "stevearc/quicker.nvim",
    event = "VeryLazy",
    ft = "qf",
    ---@module "quicker"
    ---@type quicker.SetupOptions
    opts = {},
    keys = {
        {
            "<C-q>",
            function()
                require("quicker").toggle()
            end,
            desc = "Toggle quickfix",
        },
    },
}
