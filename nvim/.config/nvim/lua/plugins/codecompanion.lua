return {
    "olimorris/codecompanion.nvim",
    dependencies = {
        {
            "MeanderingProgrammer/render-markdown.nvim",
            ft = { "markdown", "codecompanion" },
        },
    },
    cmd = { "CodeCompanionChat", "CodeCompanion" },
    opts = {
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
