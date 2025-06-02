return {
    "olimorris/codecompanion.nvim",
    dependencies = {
        "ravitemer/mcphub.nvim",
        {
            "MeanderingProgrammer/render-markdown.nvim",
            ft = { "markdown", "codecompanion" },
        },
    },
    cmd = { "CodeCompanionChat", "CodeCompanion" },
    opts = {
        extensions = {
            mcphub = {
                callback = "mcphub.extensions.codecompanion",
                opts = {
                    make_vars = true,
                    make_slash_commands = true,
                    show_result_in_chat = true,
                },
            },
        },
        strategies = {
            inline = {
                keymaps = {
                    accept_change = {
                        modes = { n = "<leader>ay" },
                        description = "Accept the suggested change",
                    },
                    reject_change = {
                        modes = { n = "<leader>an" },
                        description = "Reject the suggested change",
                    },
                },
            },
        },
    },
}
