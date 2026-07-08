-- 1. Code blocks: no background, dim italic
-- 2. Empty role labels
-- 3. Hide reasoning

tui.theme.set {
  styles = {
    ["md.code_block"] = { fg = "dim", italic = true },
    ["ok"]            = { fg = "green" },
    ["err"]           = { fg = "red", bold = true },
    ["tool"]          = { fg = "white" },
    ["accent"]        = { fg = "yellow" },
    ["tool.running"]  = { fg = "yellow" },
  },
}

tui.transcript.labels    = { user = "", assistant = "" }
-- tui.transcript.show_reasoning = false
