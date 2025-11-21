return {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    dependencies = { "nvim-mini/mini.icons" },
    opts = {},
    keys = {
        { "<leader>tt", "<cmd>FzfLua files<cr>", desc = "Files" },
    },
}
