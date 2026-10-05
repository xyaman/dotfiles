return {
    "saghen/blink.cmp",
    version = "1.*",
    opts = {
        keymap = { preset = "default" },
        sources = {
            default = { "lsp", "path", "buffer" },
        },
        completion = {
            menu = {
                border = "rounded",
            },
            documentation = {
                auto_show = true,
                window = { border = "rounded" },
            },
        },
        signature = {
            enabled = true,
            window = { border = "rounded" },
        },
    },
}
