vim.api.nvim_create_user_command("ToggleFormat", function()
    vim.g.autoformat = not vim.g.autoformat
    vim.notify(string.format("%s formatting...", vim.g.autoformat and "Enabling" or "Disabling"), vim.log.levels.INFO)
end, { desc = "Toggle autoformat (conform.nvim)" })

vim.api.nvim_create_user_command("Encoding", function()
    if vim.fn.executable("chardet") == 0 then
        vim.notify("chardet is not installed", vim.log.levels.ERROR)
        return
    end

    local obj = vim.system({ "chardet", vim.api.nvim_buf_get_name(0) }, { text = true }):wait()
    local chardet, confidence = string.match(obj.stdout, ":%s*(%S+)%s+with%s+confidence%s+(%S+)")

    local encodings = {
        { chardet, confidence },
        "euc-jp",
        "sjis",
        "utf-8",
    }
    vim.ui.select(encodings, {
        prompt = "Select encoding",
        format_item = function(item)
            if type(item) == "string" then
                return item
            else
                return string.format("chardet: %s [c: %s]", item[1], item[2])
            end
        end,
    }, function(choice)
        if choice == nil then
            return
        end

        local encoding = type(choice) == "string" and choice or choice[1]
        local filename = vim.fn.expand("%:p")

        local cmd = string.format("edit ++enc=%s %s", encoding, vim.fn.fnameescape(filename))
        vim.cmd(cmd)
    end)
end, { desc = "Select encoding" })

vim.keymap.set("n", "<leader>enc", ":Encoding<CR>", { desc = "List encodings" })
