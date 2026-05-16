return {
    "nvim-treesitter/nvim-treesitter",
    lazy = false, -- Plugin does NOT support lazy-loading
    branch = "main",
    build = ":TSUpdate",
    dependencies = {
        {
            "nvim-treesitter/nvim-treesitter-context",
            opts = {
                enabled = true,
                max_lines = 3,
                min_window_height = 20,
            },
            keys = {
                {
                    "[c",
                    function()
                        if vim.wo.diff then
                            return "[c"
                        else
                            vim.schedule(function()
                                require("treesitter-context").go_to_context()
                            end)
                            return "<Ignore>"
                        end
                    end,
                    desc = "Jump to upper context",
                    expr = true,
                },
            },
        },
    },

    config = function()
        -- Setup nvim-treesitter (minimal - only sets install directory)
        require("nvim-treesitter").setup({
            install_dir = vim.fn.stdpath("data") .. "/site",
        })

        -- Auto-enable treesitter highlighting with large file protection
        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("treesitter_highlight", { clear = true }),
            callback = function(args)
                local bufnr = args.buf
                local bufname = vim.fn.bufname(bufnr)
                local filetype = vim.bo[bufnr].filetype

                -- Skip special filetypes without treesitter parsers
                local skip_filetypes = {
                    fzf = true,
                    git = true,
                    gitcommit = true,
                    help = true,
                    man = true,
                    qf = true,
                    terminal = true,
                    prompt = true,
                    dashboard = true,
                    alpha = true,
                    neo_tree = true,
                    oil = true,
                    lazy = true,
                    mason = true,
                    lspinfo = true,
                    notify = true,
                    nofile = true,
                }

                if skip_filetypes[filetype] or vim.bo[bufnr].buftype ~= "" then
                    return
                end

                -- Get treesitter language name for this filetype
                local lang = vim.treesitter.language.get_lang(filetype)
                if not lang then
                    return
                end

                -- Check if parser is actually installed (searches full runtimepath)
                local has_parser = #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".so", false) > 0
                if not has_parser then
                    return
                end

                -- Check file size limits
                local file_size = vim.fn.getfsize(bufname)
                local file_lines = vim.api.nvim_buf_line_count(bufnr)

                -- Only start treesitter if file is not too large.
                -- Use a 5 MB cap to avoid disabling Treesitter for normal files.
                if file_size <= 5 * 1024 * 1024 and file_lines <= 10000 then
                    pcall(vim.treesitter.start, bufnr, lang)
                end
            end,
            desc = "Auto-enable treesitter highlighting",
        })
    end,
}
