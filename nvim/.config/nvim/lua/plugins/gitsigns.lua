return {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {},
    keys = {
        { "<leader>hn", "<cmd>lua require'gitsigns'.nav_hunk('next')<CR>", desc = "Next hunk" },
        { "<leader>hp", "<cmd>lua require'gitsigns'.nav_hunk('prev')<CR>", desc = "Previous hunk" },
        { "<leader>hs", "<cmd>lua require'gitsigns'.stage_hunk()<CR>", desc = "Stage hunk" },
        { "<leader>hu", "<cmd>lua require'gitsigns'.undo_stage_hunk()<CR>", desc = "Undo stage hunk" },
        { "<leader>hr", "<cmd>lua require'gitsigns'.reset_hunk()<CR>", desc = "Reset hunk" },
        { "<leader>hR", "<cmd>lua require'gitsigns'.reset_buffer()<CR>", desc = "Reset buffer" },
        { "<leader>hv", "<cmd>lua require'gitsigns'.preview_hunk()<CR>", desc = "Preview hunk" },
        { "<leader>hb", "<cmd>lua require'gitsigns'.blame_line()<CR>", desc = "Blame line" },
        { "<leader>hS", "<cmd>lua require'gitsigns'.stage_buffer()<CR>", desc = "Stage buffer" },
        { "<leader>hU", "<cmd>lua require'gitsigns'.reset_buffer_index()<CR>", desc = "Reset buffer index" },
    },
}
