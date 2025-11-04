return {
    name = "Odin Build/Test",

    builder = function(params)
        return {
            cmd = { "odin" },
            args = { "test", "src" },
            components = {
                "default",
                {
                    "on_output_parse",
                    parser = {
                        problem_matcher = {
                            -- Matches lines like: /path/file.odin(28:5) Error: message...
                            pattern = "([^%(]+)%((%d+):(%d+)%)%s+([A-Za-z]+):%s+(.*)",
                            groups = { "filename", "lnum", "col", "severity", "message" },

                            severity = {
                                ["Error"] = vim.diagnostic.severity.ERROR,
                                ["Warning"] = vim.diagnostic.severity.WARN,
                            },
                        },
                    },
                },
                "on_result_diagnostics",
                {
                    "on_result_diagnostics_quickfix",
                    open = true, -- auto-open quickfix window
                },
            },
        }
    end,
    desc = "Build or test Odin project and show compiler errors in quickfix",
    tags = { require("overseer").TAG.BUILD },
}
