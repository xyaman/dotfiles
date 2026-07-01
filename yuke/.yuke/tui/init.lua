-- 1. Code blocks: no background, dim italic
-- 2. User card background
-- 3. Empty role labels
-- 4. Hide reasoning

tui.theme.set {
  styles = {
    ["md.code_block"] = { fg = "dim", italic = true },
    ["user_card"]     = { bg = "#303030" },
    ["ok"]            = { fg = "green" },
    ["err"]           = { fg = "red", bold = true },
  },
}

tui.transcript.labels    = { user = "", assistant = "" }
tui.transcript.reasoning = "hide"

tui.transcript.highlight = function(msg)
  if msg.role == "user" then return "user_card" end
end

-- Minimal, context-aware tool rendering.
-- Calls show the key argument; results show ✓/✗ or the diff.

local c = tui.widget.content

-- Shorten a path to its last two components: /a/b/c/d.rs -> c/d.rs
local function short(path)
  if not path then return "" end
  local parent, base = path:match("([^/]+)/([^/]+)$")
  return base and (parent .. "/" .. base) or path
end

tui.transcript.render("tool_call", function(call)
  local name = call.name
  local a = call.arguments or {}
  local marker = call.running and "● " or "→ "
  local label

  if name == "read" then
    label = short(a.path) or "read"
  elseif name == "bash" then
    local cmd = (a.command or ""):match("^%s*(.-)%s*$") or ""
    if #cmd > 60 then cmd = cmd:sub(1, 57) .. "…" end
    label = cmd
    if a.cwd and a.cwd ~= "" then label = label .. "  (" .. a.cwd .. ")" end
  elseif name == "write" then
    label = "write " .. (short(a.path) or "?")
  elseif name == "edit" then
    label = "edit " .. (short(a.path) or "?")
  else
    label = name
  end

  return c.line { { marker, "tool" }, { label, "dim" } }
end)

tui.transcript.render("tool_result", function(r)
  local v = r.view
  -- write/edit: show the diff
  if v and v.kind == "diff" then
    return tui.diff_view(v.diff)
  end

  -- everything else: ✓ or ✗ based on content
  local ok = true
  local content = r.content or ""
  if r.name == "bash" then
    local code = content:match("%[exit code:%s*(%d+)%]")
    ok = code == "0"
  else
    -- read/glob/etc: non-empty content with no leading error
    ok = content ~= "" and not content:match("^%s*$")
  end

  local mark = ok and "✓" or "✗"
  local style = ok and "ok" or "err"
  local name = r.name ~= "" and r.name or "tool"
  return c.line { { "⮑ " .. mark .. " " .. name, style } }
end)
