return {
    "cbochs/grapple.nvim",
    opts = {
        icons = false,
    },
    keys = {
        { "<leader>a", "<cmd>Grapple toggle<cr>", desc = "Tag a file" },
        { "<C-s>", "<cmd>Grapple toggle_tags<cr>", desc = "Toggle tags menu" },
        { "<leader>j", "<cmd>Grapple select index=1<cr>", desc = "Select first tag" },
        { "<leader>k", "<cmd>Grapple select index=2<cr>", desc = "Select second tag" },
        { "<leader>l", "<cmd>Grapple select index=3<cr>", desc = "Select third tag" },
        { "<leader>;", "<cmd>Grapple select index=4<cr>", desc = "Select fourth tag" },
    },
}
