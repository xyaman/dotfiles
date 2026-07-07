return {
    "mason-org/mason.nvim",
    opts = {
        -- Mason package names — must mirror the lspconfig server list in plugins/lsp.lua.
        ensure_installed = {
            "lua-language-server",
            "typescript-language-server",
            "pyright",
            "rust-analyzer",
            "clangd",
            "json-lsp",
            "yaml-language-server",
            "bash-language-server",
            "html",
            "css-lsp",
            "tailwindcss-language-server",
            "ruby-lsp",
            "phpactor",
            "dockerfile-language-server",
            "zls",
        },
    },
}
