return {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    opts = {
        formatters_by_ft = {
            lua = { "stylua" },
            javascript = { "prettierd", "prettier", stop_after_first = true },
            typescript = { "prettierd", "prettier", stop_after_first = true },
            typescriptreact = { "prettierd", "prettier", stop_after_first = true },
            javascriptreact = { "prettierd", "prettier", stop_after_first = true },
            html = { "prettierd", "prettier", stop_after_first = true },
            css = { "prettierd", "prettier", stop_after_first = true },
            php = { "php-cs-fixer", lsp_format = "fallback" },
            zig = { "zigfmt", lsp_format = "fallback" },
            rust = { "rustfmt", lsp_format = "fallback" },
            ruby = { "rubocop", lsp_format = "fallback" },
            odin = { "odinfmt", lsp_format = "fallback" },
            -- For filetypes without a formatter:
            ["_"] = { "trim_whitespace", "trim_newlines" },
        },
        default_format_opts = { lsp_format = "fallback" },
        notify_on_error = true,
        formatters = {
            -- Require a Prettier configuration file to format.
            prettier = { require_cwd = true },
            prettierd = { require_cwd = true },
        },
        format_on_save = function(bufnr)
            -- Disable with a global or buffer-local variable
            if vim.g.autoformat == false or vim.b[bufnr].autoformat == false then
                return
            end

            return { timeout_ms = 500, lsp_format = "fallback" }
        end,
    },
    init = function()
        vim.g.autoformat = true
    end,
    keys = {
        {
            "<leader>cf",
            function()
                require("conform").format()
            end,
            desc = "Format code using conform.nvim",
        },
    },
}
