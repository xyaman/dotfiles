return {
    "sschleemilch/slimline.nvim",
    opts = {
        style = "fg",
        components = {
            left = { "mode", "path" },
            right = { "diagnostics", "filetype_lsp", "progress" },
        },
        configs = {
            diagnostics = {
                workspace = true,
            },
            mode = {
                verbose = true,
            },
            filetype_lsp = {
                hl = {
                    secondary = "Normal",
                },
            },
        },
    },
}
