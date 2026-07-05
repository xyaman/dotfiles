-- yuke claude-bridge provider.
--
-- Registers claude-bridge/<model>. Each agent run drives a node helper that runs
-- the Agent SDK with yuke's tools exposed via MCP. The helper stays alive across
-- rounds (tool results feed straight back). A CC session is synced from yuke's
-- messages and resumed across agent runs to keep CC's prompt cache warm.

local json = yuke.json

local helper_path = package.searchpath("tools.bridge", package.path):match("(.*/)") .. "bridge-helper.mjs"

-- Helper process, alive for one agent run.
local helper = nil

-- CC session id preserved across agent runs for resume. Cleared on compaction.
local saved_session = nil

local function helper_send(obj)
  helper.proc:write(json.encode(obj))
end

local function helper_recv(timeout)
  local line = helper.proc:readline({ timeout_ms = timeout or 60000 })
  if line == nil then error("claude-bridge: helper closed the stream") end
  return json.decode(line)
end

local function map_tools(tools)
  local out = {}
  for _, t in ipairs(tools) do
    table.insert(out, { name = t.name, description = t.description, parameters = t.parameters })
  end
  return out
end

local function spawn_helper(req)
  helper = { proc = yuke.proc.spawn({ "node", helper_path }, { env = {} }) }
  local hello = helper_recv(10000)
  if hello.type ~= "hello" then error("claude-bridge: expected hello") end
  helper_send({
    type = "init",
    system = req.system,
    model = req.model,
    effort = req.reasoning,
    tools = map_tools(req.tools),
    messages = req.messages,
    session_id = saved_session,
  })
  local ready = helper_recv(15000)
  if ready.type ~= "ready" then error("claude-bridge: expected ready, got " .. (ready.type or "?")) end
  saved_session = ready.session_id
end

-- Drain helper output into `out`. tool_use ends the round (engine runs the tool).
local function drain(out)
  while true do
    local msg = helper_recv()
    local t = msg.type
    if t == "text" then out:text(msg.delta)
    elseif t == "reasoning" then out:reasoning(msg.delta)
    elseif t == "tool_use" then
      out:tool_call({ id = msg.id, name = msg.name, arguments = msg.arguments })
      out:done({ stop_reason = "tool_calls" })
      return
    elseif t == "done" then
      if msg.usage then out:usage(msg.usage) end
      if msg.session_id then saved_session = msg.session_id end
      out:done({ stop_reason = msg.stop_reason or "stop" })
      return
    elseif t == "error" then
      out:error(msg.message or "unknown error")
      return
    end
  end
end

local function map_tools(tools)
  local out = {}
  for _, t in ipairs(tools) do
    table.insert(out, { name = t.name, description = t.description, parameters = t.parameters })
  end
  return out
end

-- Extract the last user message's text (the prompt driving this agent run).
local function last_user_text(messages)
  for i = #messages, 1, -1 do
    local m = messages[i]
    if m.role == "user" then
      if type(m.content) == "string" then return m.content end
      local parts = {}
      for _, p in ipairs(m.content) do
        if p.type == "text" then table.insert(parts, p.text) end
      end
      return table.concat(parts, "\n")
    end
  end
  return ""
end

-- Flatten a tool-result message's content to text.
local function tool_text(content)
  if type(content) == "string" then return content end
  local parts = {}
  for _, p in ipairs(content) do
    if p.type == "text" then table.insert(parts, p.text) end
  end
  return table.concat(parts, "\n")
end

local models = {
  { name = "opus",   context_window = 200000, reasoning_levels = { "low", "medium", "high" } },
  { name = "sonnet", context_window = 200000 },
  { name = "haiku",  context_window = 200000 },
}

yuke.provider {
  name = "claude-bridge",
  models = models,
  stream = function(req, out)
    -- Round 1 of an agent run: spawn helper, sync session, drive the user turn.
    if helper == nil then
      spawn_helper(req)
      helper_send({ type = "turn", prompt = last_user_text(req.messages) })
      drain(out)
      return
    end
    -- Continuation round: feed the pending tool result(s), then drain. The engine
    -- appends tool-result messages after our tool_use; match by tool_call_id.
    for _, m in ipairs(req.messages) do
      if m.role == "tool" and m.tool_call_id then
        helper_send({ type = "tool_result", id = m.tool_call_id, content = tool_text(m.content) })
      end
    end
    drain(out)
  end,
}

-- Route compaction through the same backend. Returns { summary = ... }.
yuke.on("before_compact", function(messages)
  if helper == nil then return nil end
  local prompt = "Summarize this conversation, preserving key context and decisions:\n\n"
  for _, m in ipairs(messages) do
    local role = m.role
    local text = type(m.content) == "string" and m.content or tool_text(m.content)
    if text and text ~= "" then prompt = prompt .. role .. ": " .. text .. "\n" end
  end
  helper_send({ type = "summarize", prompt = prompt })
  while true do
    local msg = helper_recv()
    if msg.type == "summarize_done" then
      -- Compaction rewrites history; the saved CC session is now stale.
      saved_session = nil
      return { summary = msg.text }
    elseif msg.type == "summarize_error" then
      yuke.log("claude-bridge compaction failed: " .. (msg.message or "?"), "warn")
      return nil
    end
  end
end)

-- Tear down the helper at run end; keep saved_session for the next run's resume.
yuke.on("agent_end", function()
  if helper then
    pcall(function() helper.proc:kill() end)
    helper = nil
  end
end)
