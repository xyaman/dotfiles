local M = {}
local max_bytes = 5 * 1024 * 1024
local max_lines = 10000

local function detach(buf)
    vim.treesitter.stop(buf)
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if vim.wo[win].foldexpr == "v:lua.vim.treesitter.foldexpr()" then
            vim.wo[win].foldmethod = "manual"
        end
    end
    return false
end

function M.attach(buf)
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return false
    end
    if vim.bo[buf].buftype ~= "" or vim.api.nvim_buf_line_count(buf) > max_lines then
        return detach(buf)
    end
    local size = vim.fn.getfsize(vim.api.nvim_buf_get_name(buf))
    if size > max_bytes or vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) > max_bytes then
        return detach(buf)
    end

    local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
    if not lang then
        return detach(buf)
    end
    local loaded, parser = pcall(vim.treesitter.language.add, lang)
    if not loaded or not parser then
        return detach(buf) -- No parser: keep normal syntax highlighting and manual folds.
    end
    local ok, err = pcall(vim.treesitter.start, buf, lang)
    if not ok then
        vim.notify("Treesitter: " .. tostring(err), vim.log.levels.WARN)
        return detach(buf)
    end
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        vim.wo[win].foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.wo[win].foldmethod = "expr"
    end
    return true
end

function M.install()
    local treesitter = require("nvim-treesitter")
    local installed = treesitter.get_installed("parsers")
    local missing = vim.tbl_filter(function(lang)
        return not vim.tbl_contains(installed, lang)
    end, require("config.languages").parsers)
    -- Force missing libraries even if a previous failed install left a queries directory.
    local task = treesitter.install(missing, { force = true })
    task:await(vim.schedule_wrap(function(err, success)
        if err or success == false then
            vim.notify(
                "Parser installation incomplete; see :messages and retry :TSInstallConfigured",
                vim.log.levels.WARN
            )
        end
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            M.attach(buf)
        end
    end))
    return task
end

function M.setup()
    require("nvim-treesitter").setup({})
    local group = vim.api.nvim_create_augroup("DotfilesTreesitter", { clear = true })
    vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
        group = group,
        callback = function(ev)
            M.attach(ev.buf)
        end,
        desc = "Enable Treesitter highlighting/folds when a parser is available",
    })
    vim.api.nvim_create_user_command("TSInstallConfigured", M.install, {
        desc = "Install the configured Treesitter parsers and reattach open buffers",
    })
    -- Don't start background downloads during headless checks / Lazy restore.
    if #vim.api.nvim_list_uis() > 0 then
        M.install()
    end
end

return M
