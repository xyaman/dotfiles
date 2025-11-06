return {
    "stevearc/overseer.nvim",
    opts = {
        dap = false,
        task_list = {
            -- direction = "bottom",
            max_width = { 600, 0.7 },
            bindings = {
                ["g?"] = false,
                ["<C-l>"] = false,
                ["<C-h>"] = false,
                ["<C-q"] = false,
                ["{"] = false,
                ["}"] = false,
            },
        },
        component_aliases = {
            -- Tasks from tasks.json use these components
            default_vscode = {
                "default",
                { "on_result_diagnostics_quickfix", open = true },
            },
        },
    },
    keys = {
        {
            "<leader>ot",
            "<cmd>OverseerToggle<cr>",
            desc = "Toggle task window",
        },
        {
            "<leader>o<",
            function()
                local overseer = require("overseer")
                local tasks = overseer.list_tasks({ recent_first = true })

                if vim.tbl_isempty(tasks) then
                    vim.notify("No tasks found", vim.log.levels.WARN)
                    return
                end

                local task = tasks[1]

                -- if the task is stuck, failed, or canceled, it can’t be restarted directly
                if vim.tbl_contains({ "PENDING", "FAILURE", "CANCELED" }, task.status) then
                    local name = (task.metadata and task.metadata.template) or task.name
                    overseer.run_action(task, "dispose")

                    if name then
                        overseer.run_template({ name = name })
                        vim.notify("Task recreated from template: " .. name, vim.log.levels.INFO)
                    else
                        vim.notify("Cannot restart: no template or command found", vim.log.levels.ERROR)
                    end
                else
                    overseer.run_action(task, "restart")
                    vim.notify("Task restarted", vim.log.levels.INFO)
                end
            end,
            desc = "Restart last Overseer task",
        },
        {
            "<leader>or",
            "<cmd>OverseerRun<cr>",
            desc = "Run task",
        },
    },
}
