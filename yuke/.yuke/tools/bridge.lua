-- yuke claude-bridge provider.
--
-- Registers claude-bridge/<model> as a real yuke provider. Each turn drives a
-- node helper (bridge-helper.mjs) that runs the Agent SDK with yuke's tools
-- exposed via MCP. The helper stays alive across rounds so tool results feed
-- straight back.

local json = yuke.json

-- Path to the helper, beside this file (resolved via package.path).
local helper_path = package.searchpath("tools.bridge", package.path):match("(.*/)") .. "bridge-helper.mjs"

-- Per-turn helper state. Held in a module upvalue so it survives across rounds
-- within one agent run, and is torn down on agent_end.
local helper = nil

local function helper_send(obj)
  helper.proc:write(json.encode(obj))
end

local function helper_recv(timeout)
  local line = helper.proc:readline({ timeout_ms = timeout or 60000 })
  if line == nil then error("claude-bridge: helper closed the stream") end
  return json.decode(line)
end

-- Drain helper output, forwarding to `out`. Returns when the helper emits a
-- terminal event (done/error). A tool_use ends the round (engine runs the tool).
local function drain(out)
  while true do
    local msg = helper_recv()
    local t = msg.type
    if t == "text" then
      out:text(msg.delta)
    elseif t == "reasoning" then
      out:reasoning(msg.delta)
    elseif t == "tool_use" then
      out:tool_call({ id = msg.id, name = msg.name, arguments = msg.arguments })
      out:done({ stop_reason = "tool_calls" })
      return
    elseif t == "done" then
      if msg.usage then out:usage(msg.usage) end
      out:done({ stop_reason = msg.stop_reason or "stop" })
      return
    elseif t == "error" then
      out:error(msg.message or "unknown error")
      return
    end
    -- hello/ready/etc: ignore
  end
end

-- Map yuke tool schemas to the shape the helper expects.
local function map_tools(tools)
  local out = {}
  for _, t in ipairs(tools) do
    table.insert(out, {
      name = t.name,
      description = t.description,
      parameters = t.parameters,
    })
  end
  return out
end

-- Build the assistant prompt the SDK expects. yuke gives us the full message
-- list; we only need the latest user turn (the SDK owns its own session).
-- For round-1 we pass the user message; subsequent rounds pass the tool result
-- via the helper's stdin tool_result handler.
local function last_user_text(messages)
  for i = #messages, 1, -1 do
    local m = messages[i]
    if m.role == "user" and m.content then
      if type(m.content) == "string" then return m.content end
      -- multimodal: concatenate text parts
      local parts = {}
      for _, p in ipairs(m.content) do
        if p.type == "text" then table.insert(parts, p.text) end
      end
      return table.concat(parts, "\n")
    end
  end
  return messages[#messages].content or ""
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
    -- Lazy-spawn the helper on first round of a turn.
    if helper == nil then
      helper = { proc = yuke.proc.spawn({ "node", helper_path }, { env = {} }) }
      -- Wait for hello.
      local hello = helper_recv(10000)
      if hello.type ~= "hello" then error("claude-bridge: expected hello from helper") end
      -- Init with tools, system, model.
      helper_send({
        type = "init",
        system = req.system,
        model = req.model,
        effort = req.reasoning,
        tools = map_tools(req.tools),
        cwd = nil,
      })
      local ready = helper_recv(10000)
      if ready.type ~= "ready" then error("claude-bridge: expected ready from helper") end
    end

    -- If there is a pending tool result (we were re-entered after a tool round),
    -- feed it to the helper before starting the next turn.
    -- The engine appends the tool result to req.messages; find it.
    local last = req.messages[#req.messages]
    if last and last.role == "tool" then
      -- tool result message: deliver to helper by id
      local content = last.content
      if type(content) ~= "string" then
        -- multimodal tool result: flatten
        local parts = {}
        for _, p in ipairs(content) do
          if p.type == "text" then table.insert(parts, p.text) end
        end
        content = table.concat(parts, "\n")
      end
      -- The tool_call_id is on the message; the helper keys by the id we sent.
      helper_send({ type = "tool_result", id = last.tool_call_id, content = content })
    end

    -- Drive the turn.
    helper_send({ type = "turn", prompt = last_user_text(req.messages) })
    drain(out)
  end,
}

-- Tear down the helper at run end so it never leaks.
yuke.on("agent_end", function()
  if helper then
    pcall(function() helper.proc:kill() end)
    helper = nil
  end
end)
