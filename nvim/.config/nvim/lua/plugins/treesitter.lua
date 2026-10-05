return {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    branch = "main",
    build = ":TSUpdate",
    dependencies = {
        {
            "nvim-treesitter/nvim-treesitter-context",
            opts = { max_lines = 3, min_window_height = 20 },
            keys = {
                {
                    "[c",
                    function()
                        if vim.wo.diff then
                            return "[c"
                        end
                        vim.schedule(function()
                            require("treesitter-context").go_to_context()
                        end)
                        return "<Ignore>"
                    end,
                    desc = "Jump to upper context",
                    expr = true,
                },
            },
        },
    },
    config = function()
        require("config.treesitter").setup()
    end,
}
