-- Reset highlighting.
vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then
    vim.cmd.syntax("reset")
end
vim.o.termguicolors = true
vim.g.colors_name = "tsoding"

local c = {
    fg = "#cdd6f4",
    bg = "#181818",
    bg_darker = "#101010",
    white = "#cdd6f4",
    gray = "#282828",
    green = "#73d936",
    red = "#f43841",
    yellow = "#ffdd33",
    brown = "#cc8c3c",
    blue = "#519fdf",
    cyan = "#46a6b2",
    orange = "#c18a56",
    purple = "#b668cd",
    magenta = "#d16d9e",

    highlight = "#79bf46", -- green
}

local hl = vim.api.nvim_set_hl

-- highlights
hl(0, "Normal", { fg = c.fg, bg = c.bg })
hl(0, "NormalFloat", { fg = c.fg, bg = c.bg_darker })
hl(0, "FloatBorder", { fg = c.fg, bg = c.bg })
hl(0, "NormalNC", { fg = c.fg, bg = c.bg }) -- Normal non current
hl(0, "NormalSB", { fg = c.fg, bg = c.bg_darker }) -- Normal text in side bar
hl(0, "Pmenu", { fg = c.fg, bg = c.bg_darker }) -- Completion window
hl(0, "PmenuSel", { fg = c.green, bg = c.bg }) -- Completion window selection
hl(0, "SignColumn", { fg = "NONE", bg = c.bg })
hl(0, "CursorLineNr", { fg = c.yellow, bg = "NONE", bold = true })
hl(0, "Statement", { fg = c.yellow, bg = "NONE", bold = true })
hl(0, "CursorLine", { fg = "NONE", bg = c.gray })
hl(0, "StatusLine", { fg = c.fg, bg = c.gray })

hl(0, "CurSearch", { fg = c.bg, bg = c.highlight })
hl(0, "IncSearch", { link = "CurSearch" })

-- special words
hl(0, "Comment", { fg = c.brown, bg = "NONE" })
hl(0, "Special", { fg = c.fg, bg = "NONE", bold = true })
hl(0, "@variable", { fg = c.fg, bg = "NONE" })
hl(0, "Constant", { fg = c.fg, bg = "NONE" })
hl(0, "Function", { fg = c.fg, bg = "NONE" })
hl(0, "String", { fg = c.green, bg = "NONE" })
hl(0, "Identifier", { fg = c.fg, bg = "NONE" })
hl(0, "Title", { fg = c.yellow, bg = "NONE", bold = true })
hl(0, "Type", { fg = c.fg, bg = "NONE", bold = true })

-- diagnostics
hl(0, "DiagnosticError", { fg = c.red, bg = "NONE", bold = true })
hl(0, "DiagnosticWarn", { fg = c.yellow, bg = "NONE", bold = true })
hl(0, "DiagnosticHint", { fg = c.cyan, bg = "NONE", bold = true })

-- lsp
hl(0, "LspSignatureActiveParameter", { bold = true, underline = true, sp = c.fg })
