return {
    "stevearc/quicker.nvim",
    event = "VeryLazy",
    ft = "qf",
    ---@module "quicker"
    ---@type quicker.SetupOptions
    opts = {},
    keys = {
        { "<C-q>", ":lua require('quicker').toggle()<cr>", desc = "Toggle quickfix" },
    },
}
