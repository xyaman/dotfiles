--- Diff viewer for working-tree changes; pairs with gitsigns.nvim (which handles
--- inline hunks). Lets you review all unstaged/staged changes in a dedicated tab.
return {
    "sindrets/diffview.nvim",
    keys = {
        { "<leader>do", "<cmd>DiffviewOpen<cr>", desc = "Diff: open review tab" },
        { "<leader>dc", "<cmd>DiffviewClose<cr>", desc = "Diff: close review tab" },
        { "<leader>dh", "<cmd>DiffviewFileHistory<cr>", desc = "Diff: file history" },
        { "<leader>dr", "<cmd>DiffviewRefresh<cr>", desc = "Diff: refresh" },
    },
}