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
                border = "single",
            },
            documentation = {
                auto_show = true,
                window = { border = "single" },
            },
        },
        signature = {
            enabled = true,
            window = { border = "single" },
        },
    },
}
