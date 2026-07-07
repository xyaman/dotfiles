return {
    "neovim/nvim-lspconfig",
    config = function()
        -- Lean server list — nvim-lspconfig supplies default cmd/filetypes/root_markers.
        -- Mason installs the binaries (see plugins/mason.lua); this just enables them.
        -- Note: lspconfig server names (e.g. "lua_ls") differ from Mason package names
        -- (e.g. "lua-language-server") — keep both lists in sync when adding a language.
        vim.lsp.enable({
            "lua_ls",
            "ts_ls",
            "pyright",
            "rust_analyzer",
            "clangd",
            "jsonls",
            "yamlls",
            "bashls",
            "html",
            "cssls",
            "tailwindcss",
            "ruby_lsp",
            "phpactor",
            "dockerls",
            "zls",
        })

        vim.api.nvim_create_autocmd("LspAttach", {
            callback = function(ev)
                local b = { buffer = ev.buf }
                vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", b, { desc = "Go to definition" }))
                vim.keymap.set("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", b, { desc = "Go to declaration" }))
                vim.keymap.set("n", "gi", vim.lsp.buf.implementation, vim.tbl_extend("force", b, { desc = "Go to implementation" }))
                vim.keymap.set("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", b, { desc = "Go to references" }))
                vim.keymap.set("n", "gt", vim.lsp.buf.type_definition, vim.tbl_extend("force", b, { desc = "Go to type definition" }))
                vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", b, { desc = "Hover" }))
                vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, vim.tbl_extend("force", b, { desc = "Rename" }))
                vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", b, { desc = "Code action" }))
                vim.keymap.set("n", "<leader>cs", vim.lsp.buf.signature_help, vim.tbl_extend("force", b, { desc = "Signature help" }))
                vim.keymap.set("n", "<leader>ld", vim.diagnostic.open_float, vim.tbl_extend("force", b, { desc = "Show diagnostic float" }))
            end,
            desc = "LSP keymaps on attach",
        })
    end,
}