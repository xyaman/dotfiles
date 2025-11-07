-- Set up icons.
local icons = {
    Stopped = { "", "DiagnosticWarn", "DapStoppedLine" },
    Breakpoint = "",
    BreakpointCondition = "",
    BreakpointRejected = { "", "DiagnosticError" },
    LogPoint = "",
}

for name, sign in pairs(icons) do
    sign = type(sign) == "table" and sign or { sign }
    vim.fn.sign_define("Dap" .. name, {
        text = sign[1] .. " ",
        texthl = sign[2] or "DiagnosticInfo",
        linehl = sign[3],
        numhl = sign[3],
    })
end

return {
    "mfussenegger/nvim-dap",
    event = "VeryLazy",
    dependencies = {
        "igorlfs/nvim-dap-view",
        "theHamsta/nvim-dap-virtual-text",
        "jbyuki/one-small-step-for-vimkind",
    },
    config = function()
        local dap = require("dap")
        local dv = require("dap-view")
        local osv = require("osv")

        dv.setup({
            winbar = {
                sections = { "scopes", "breakpoints", "threads", "repl" },
                default_section = "scopes",
                controls = { enabled = true },
            },
            windows = { height = 12 },
            switchbuf = "usetab,uselast",
        })

        require("nvim-dap-virtual-text").setup()

        -- Use overseer for running preLaunchTask and postDebugTask.
        require("overseer").patch_dap(true)
        require("dap.ext.vscode").json_decode = require("overseer.json").decode

        -- open Dap UI automatically when debug starts (e.g. after <F5>)
        dap.listeners.before.attach["dap-view-config"] = function()
            dv.open()
        end
        dap.listeners.before.launch["dap-view-config"] = function()
            dv.open()
        end
        dap.listeners.before.event_terminated["dap-view-config"] = function()
            dv.close()
        end
        dap.listeners.before.event_exited["dap-view-config"] = function()
            dv.close()
        end

        -- mappings
        vim.keymap.set("n", "<leader>dt", "<cmd>DapViewToggle<cr>", { desc = "Toggle dap-view" })
        vim.keymap.set("n", "<F5>", "<cmd>DapContinue<cr>", { desc = "DAP: Continue" })
        vim.keymap.set("n", "<leader>db", "<cmd>DapToggleBreakpoint<cr>", { desc = "DAP: Toggle breakpoint" })
        vim.keymap.set("n", "<leader>dl", function()
            osv.launch({ port = 8086 })
        end, { desc = "Launch Lua adapter" })

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
    end,
}
