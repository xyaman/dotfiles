-- -- Set up icons.
-- local icons = {
--     Stopped = { "", "DiagnosticWarn", "DapStoppedLine" },
--     Breakpoint = "",
--     BreakpointCondition = "",
--     BreakpointRejected = { "", "DiagnosticError" },
--     LogPoint = "",

-- }

-- for name, sign in pairs(icons) do
--     sign = type(sign) == "table" and sign or { sign }
--     vim.fn.sign_define("Dap" .. name, {
--         -- stylua: ignore
--         text = sign[1] --[[@as string]] .. ' ',
--         texthl = sign[2] or "DiagnosticInfo",
--         linehl = sign[3],
--         numhl = sign[3],
--     })
-- end
return {
    "mfussenegger/nvim-dap",
    event = "VeryLazy",
    dependencies = {
        "igorlfs/nvim-dap-view",
        "theHamsta/nvim-dap-virtual-text",
        {
            "jbyuki/one-small-step-for-vimkind",
            keys = {
                {
                    "<leader>dl",
                    function()
                        require("osv").launch({ port = 8086 })
                    end,
                    desc = "Launch Lua adapter",
                },
            },
        },
    },
    config = function()
        local dap = require("dap")
        local dv = require("dap-view")

        dv.setup({
            winbar = {
                sections = { "scopes", "breakpoints", "threads", "exceptions", "repl", "console" },
                default_section = "scopes",
            },
            windows = { height = 12 },
            -- When jumping through the call stack, try to switch to the buffer if already open in
            -- a window, else use the last window to open the buffer.
            switchbuf = "usetab,uselast",
        })

        require("nvim-dap-virtual-text").setup()

        -- adapters
        dap.adapters.codelldb = {
            type = "server",
            port = "${port}",
            executable = {
                command = "codelldb",
                args = { "--port", "${port}" },
            },
        }

        dap.adapters.nlua = function(callback, config)
            callback({ type = "server", host = config.host or "127.0.0.1", port = config.port or 8086 })
        end

        -- configurations
        dap.configurations.lua = {
            {
                type = "nlua",
                request = "attach",
                name = "Attach to running Neovim instance",
            },
        }

        dap.configurations.zig = {
            {
                name = "[codellb] launch",
                type = "codelldb",
                request = "launch",
                program = function()
                    return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
                end,
                cwd = "${workspaceFolder}",
                args = {},
                -- terminal = "external",
                -- console = "externalTerminal",
            },

            {
                name = "[codellb] attach",
                type = "codelldb",
                request = "attach",
                pid = function()
                    return tonumber(vim.fn.input("PID: "))
                end,
                cwd = "${workspaceFolder}",
                args = {},
            },
        }

        -- mappings
        vim.keymap.set("n", "<F5>", function()
            dap.continue()
        end, {})

        vim.keymap.set("n", "<leader>db", function()
            dap.toggle_breakpoint()
        end)

        -- open Dap UI automatically when debug starts (e.g. after <F5>)
        dap.listeners.before.attach.dapui_config = function()
            dv.open()
        end

        dap.listeners.before.launch.dapui_config = function()
            dv.open()
        end

        -- close Dap UI with :DapCloseUI
        vim.api.nvim_create_user_command("DapCloseUI", function()
            require("dv").close()
        end, {})
    end,
}
