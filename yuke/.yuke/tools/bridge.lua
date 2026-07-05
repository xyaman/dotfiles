-- yuke claude-bridge provider.
--
-- Registers claude-bridge/<model>. Each agent run drives a node helper that runs
-- the Agent SDK with yuke's tools exposed via MCP. The helper stays alive across
-- rounds; a CC session is synced from yuke's messages and resumed across runs.

local json = yuke.json

local helper_path = package.searchpath("tools.bridge", package.path):match("(.*/)") .. "bridge-helper.mjs"

local helper = nil
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

local function tool_text(content)
  if type(content) == "string" then return content end
  local parts = {}
  for _, p in ipairs(content) do
    if p.type == "text" then table.insert(parts, p.text) end
  end
  return table.concat(parts, "\n")
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

-- Drain helper output into `out`. Collects ALL tool_use events in a round before
-- ending (handles parallel tool calls). After a tool_use, reads with a short
-- timeout to catch siblings fired concurrently by the SDK.
local function drain(out)
  local tool_calls = {}
  while true do
    local msg = helper_recv()
    local t = msg.type
    if t == "text" then
      out:text(msg.delta)
    elseif t == "reasoning" then
      out:reasoning(msg.delta)
    elseif t == "tool_use" then
      table.insert(tool_calls, { id = msg.id, name = msg.name, arguments = msg.arguments })
      -- Collect sibling tool_use events (parallel calls fire near-simultaneously).
      while true do
        local line = helper.proc:readline({ timeout_ms = 200 })
        if line == nil then break end
        local m = json.decode(line)
        if m.type == "tool_use" then
          table.insert(tool_calls, { id = m.id, name = m.name, arguments = m.arguments })
        else
          -- Unexpected event mid-collect: re-process it.
          if m.type == "done" then
            if m.usage then out:usage(m.usage) end
            if m.session_id then saved_session = m.session_id end
          end
          break
        end
      end
      for _, tc in ipairs(tool_calls) do out:tool_call(tc) end
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

local models = {
  { name = "opus",   context_window = 200000, reasoning_levels = { "low", "medium", "high" } },
  { name = "sonnet", context_window = 200000 },
  { name = "haiku",  context_window = 200000 },
}

yuke.provider {
  name = "claude-bridge",
  models = models,
  stream = function(req, out)
    if helper == nil then
      spawn_helper(req)
      helper_send({ type = "turn", prompt = last_user_text(req.messages) })
      drain(out)
      return
    end
    -- Continuation: feed pending tool result(s) by tool_call_id, then drain.
    for _, m in ipairs(req.messages) do
      if m.role == "tool" and m.tool_call_id then
        helper_send({ type = "tool_result", id = m.tool_call_id, content = tool_text(m.content) })
      end
    end
    drain(out)
  end,
}

-- Route compaction through the same backend. Passes structured messages (not
-- flattened text) so the summarizer sees tool_use/tool_result shape.
yuke.on("before_compact", function(messages)
  if helper == nil then return nil end
  helper_send({ type = "summarize", messages = messages })
  while true do
    local msg = helper_recv()
    if msg.type == "summarize_done" then
      saved_session = nil
      -- Kill the helper so the next round respawns with compacted history.
      pcall(function() helper.proc:kill() end)
      helper = nil
      return { summary = msg.text }
    elseif msg.type == "summarize_error" then
      yuke.log("claude-bridge compaction failed: " .. (msg.message or "?"), "warn")
      return nil
    end
  end
end)

-- Tear down at run end. On cancel/error, drop the saved session to avoid
-- resuming a CC session that may have orphan writes from the killed process.
yuke.on("agent_end", function(outcome)
  if helper then
    pcall(function() helper.proc:kill() end)
    helper = nil
  end
  if outcome ~= "completed" then
    saved_session = nil
  end
end)
