return {
    "neovim/nvim-lspconfig",
    dependencies = {
        "mason-org/mason.nvim",
        "mason-org/mason-lspconfig.nvim",
        "saghen/blink.cmp",
    },
    config = function()
        local languages = require("config.languages")
        local servers = languages.servers

        -- Configure before enabling any server; advertise Blink's snippet/completion support.
        vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })
        for name, config in pairs(servers) do
            vim.lsp.config(name, config)
        end

        vim.diagnostic.config({
            severity_sort = true,
            float = { border = "rounded", source = "if_many" },
        })
        vim.api.nvim_create_autocmd("LspAttach", {
            group = vim.api.nvim_create_augroup("DotfilesLsp", { clear = true }),
            callback = function(ev)
                local function map(lhs, rhs, desc)
                    vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
                end
                map("gd", vim.lsp.buf.definition, "Go to definition")
                map("gD", vim.lsp.buf.declaration, "Go to declaration")
                map("gi", vim.lsp.buf.implementation, "Go to implementation")
                map("gr", vim.lsp.buf.references, "Go to references")
                map("gt", vim.lsp.buf.type_definition, "Go to type definition")
                map("K", vim.lsp.buf.hover, "Hover")
                map("<leader>cr", vim.lsp.buf.rename, "Rename")
                map("<leader>ca", vim.lsp.buf.code_action, "Code action")
                map("<leader>cs", vim.lsp.buf.signature_help, "Signature help")
                map("<leader>ld", vim.diagnostic.open_float, "Show diagnostic float")
            end,
            desc = "LSP keymaps on attach",
        })
        local managed = vim.tbl_keys(servers)
        for name, executable in pairs(languages.prefer_external) do
            local path = vim.fn.exepath(executable)
            if path ~= "" then
                vim.lsp.config(name, { cmd = { path } })
                vim.lsp.enable(name)
                managed = vim.tbl_filter(function(server)
                    return server ~= name
                end, managed)
            end
        end
        table.sort(managed)
        require("mason-lspconfig").setup({ ensure_installed = managed, automatic_enable = managed })
    end,
}
