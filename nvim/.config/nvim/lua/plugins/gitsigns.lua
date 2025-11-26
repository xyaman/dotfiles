return {
    "lewis6991/gitsigns.nvim",
    keys = {
        { "<leader>hn", "<cmd>lua require'gitsigns'.next_hunk()<CR>", "Next hunk" },
        { "<leader>hp", "<cmd>lua require'gitsigns'.prev_hunk()<CR>", "Previous hunk" },
        { "<leader>hs", "<cmd>lua require'gitsigns'.stage_hunk()<CR>", "Stage hunk" },
        { "<leader>hu", "<cmd>lua require'gitsigns'.undo_stage_hunk()<CR>", "Undo stage hunk" },
        { "<leader>hr", "<cmd>lua require'gitsigns'.reset_hunk()<CR>", "Reset hunk" },
        { "<leader>hR", "<cmd>lua require'gitsigns'.reset_buffer()<CR>", "Reset buffer" },
        { "<leader>hp", "<cmd>lua require'gitsigns'.preview_hunk()<CR>", "Preview hunk" },
        { "<leader>hb", "<cmd>lua require'gitsigns'.blame_line()<CR>", "Blame line" },
        { "<leader>hS", "<cmd>lua require'gitsigns'.stage_buffer()<CR>", "Stage buffer" },
        { "<leader>hU", "<cmd>lua require'gitsigns'.reset_buffer_index()<CR>", "Reset buffer index" },
    },
}
