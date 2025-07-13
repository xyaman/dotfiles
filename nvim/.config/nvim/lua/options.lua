vim.opt.number = true -- shows line number
vim.opt.relativenumber = true -- shows relative line numbers
vim.opt.cursorline = true -- highlights the current line
vim.opt.smartindent = true
vim.opt.expandtab = true -- Use spaces instead of tabs
vim.opt.tabstop = 4 -- number of spaces for tab
vim.opt.shiftwidth = 4 -- number of spaces for indentation
vim.opt.ignorecase = true -- ignore search in search patterns
vim.opt.smartcase = true -- automatically switch to a case-sensitive search if there are any capital letters
vim.opt.swapfile = false -- creates a swapfile
vim.opt.backup = false
vim.opt.splitbelow = true -- force all horizontal splits go below of current window
vim.opt.splitright = true -- force all vertical splits go to the right of current window
vim.opt.updatetime = 300 -- faster completion (3000ms default)
vim.opt.wrap = false -- displays line as one long line
vim.opt.completeopt = { "menuone", "noselect" }
vim.opt.colorcolumn = "80"

-- have one statusline per window, instead of per buffer
vim.o.laststatus = 3

-- show always signcolumn (default = auto)
vim.wo.signcolumn = "yes"
vim.opt.hlsearch = false

-- Save undo history.
vim.o.undofile = true

-- Folding.
vim.o.foldcolumn = "1"
vim.o.foldlevelstart = 99
vim.wo.foldtext = ""
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"

-- UI characters.
vim.opt.fillchars = {
    eob = " ",
    fold = " ",
    foldclose = require("icons").arrows.right,
    foldopen = require("icons").arrows.down,
    foldsep = " ",
    msgsep = "─",
}

-- Sets how neovim will display certain whitespace characters in the editor.
-- See `:help 'list'`
-- and `:help 'listchars'`
vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- Floating windows (blink, etc)
vim.o.winborder = "rounded"
vim.opt.guicursor = ""

-- highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
    desc = "Highlight on yank",
    callback = function()
        -- Setting a priority higher than the LSP references one.
        -- vim.hl.on_yank { higroup = 'Visual', priority = 250, timeout = 40 }
        vim.hl.on_yank({ priority = 250, timeout = 40 })
    end,
})

-- Global variables (Languages ex.)
vim.cmd([[autocmd FileType ruby setlocal indentkeys-=.]]) -- ruby indenting
vim.cmd([[ au BufRead,BufNewFile *.zon setfiletype zig ]])
vim.filetype.add({
    pattern = { [".*/hypr/.*%.conf"] = "hyprlang" },
    extension = {
        cgi = "php",
    },
})

-- NEOVIDE (yes... i need to use it sometimes)
vim.g.neovide_position_animation_length = 0
vim.g.neovide_cursor_animation_length = 0.00
vim.g.neovide_cursor_trail_size = 0
vim.g.neovide_cursor_animate_in_insert_mode = false
vim.g.neovide_cursor_animate_command_line = false
vim.g.neovide_scroll_animation_far_lines = 0
vim.g.neovide_scroll_animation_length = 0.00
