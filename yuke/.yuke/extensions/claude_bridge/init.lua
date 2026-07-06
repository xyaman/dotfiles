-- yuke claude-bridge provider.
--
-- Registers claude-bridge/<model>. Each agent run drives a node helper that runs
-- the Agent SDK with yuke's tools exposed via MCP. The helper stays alive across
-- runs; a CC session is synced from yuke's messages and resumed across runs.
--
-- Modeled on pi-claude-bridge (https://github.com/elidickinson/pi-claude-bridge).
-- Reference commit: 756c7e6 (v0.6.1); systemPromptMode from PR #21 (593a181).

local json = yuke.json

local helper_path = package.searchpath("extensions.claude_bridge.init", package.path):match("(.*/)") .. "helper.mjs"

-- The live helper process. Nil when not spawned or after teardown. Kept alive
-- across completed runs (warm CC session); killed only on cancel/error.
local helper = nil
-- CC session id resumed across turns for prompt-cache warmth.
local saved_session = nil
-- Stop reason of the last drain. "tool_calls" = mid-turn; else = idle.
local last_stop = nil
-- Model the helper was initialized with; a switch forces re-init.
local init_model = nil
-- User messages queued mid-turn, replayed as continuation turns after the
-- current SDK query ends (modeled on pi-claude-bridge's deferredUserMessages).
local deferred_prompts = {}

-- Configurable SDK plumbing. All optional; setup() merges over these defaults.
local config = {
  claude_path = nil,                    -- override claude binary
  system_prompt_mode = "replace",       -- "replace" | "preset" | "none"
  setting_sources = {},                 -- {"user","project","local"} or {} for isolation
  skills = {},                          -- CC skill names
  strict_mcp_config = true,             -- suppress filesystem/cloud MCP servers
  include_partial_messages = true,      -- stream deltas
  thinking_display = "summarized",      -- "omitted"|"summarized"|"interleaved"|nil
}

local M = {}

function M.setup(opts)
  opts = opts or {}
  for k, _ in pairs(config) do
    if opts[k] ~= nil then config[k] = opts[k] end
  end
  return M
end

local function helper_send(obj)
  helper.proc:write(json.encode(obj))
end

-- Errors on EOF. With timeout: returns nil on timeout. Without timeout: waits
-- indefinitely (run cancellation kills the helper group).
local function helper_recv(timeout)
  local line, closed = helper.proc:readline({ timeout_ms = timeout })
  if closed then error("claude-bridge: helper process exited") end
  if line == nil then error("claude-bridge: helper timed out") end
  return json.decode(line)
end

-- Soft variant for the sibling-collect loop: returns nil on timeout, errors on EOF.
local function helper_recv_optional(timeout)
  local line, closed = helper.proc:readline({ timeout_ms = timeout })
  if closed then error("claude-bridge: helper process exited") end
  if line == nil then return nil end
  return json.decode(line)
end

local function map_tools(tools)
  local out = {}
  for _, t in ipairs(tools) do
    table.insert(out, { name = t.name, description = t.description, parameters = t.parameters })
  end
  return out
end

-- Extract text from a single user message.
local function user_text(msg)
  if type(msg.content) == "string" then return msg.content end
  local parts = {}
  for _, p in ipairs(msg.content) do
    if p.type == "text" then table.insert(parts, p.text) end
  end
  return table.concat(parts, "\n")
end

local function tool_text(content)
  if type(content) == "string" then return content end
  local parts = {}
  for _, p in ipairs(content) do
    if p.type == "text" then table.insert(parts, p.text) end
  end
  return table.concat(parts, "\n")
end

-- Walk backwards from the end of messages until the last assistant message,
-- collecting trailing tool results and user messages in order. Tool results
-- are forwarded to the helper; user messages are deferred for replay.
local function split_trailing(messages)
  local tool_results = {}
  local user_prompts = {}
  for i = #messages, 1, -1 do
    local m = messages[i]
    if m.role == "assistant" then break end
    if m.role == "tool" and m.tool_call_id then
      table.insert(tool_results, 1, { id = m.tool_call_id, content = tool_text(m.content) })
    elseif m.role == "user" then
      local text = user_text(m)
      if text and text ~= "" then
        table.insert(user_prompts, 1, text)
      end
    end
  end
  return tool_results, user_prompts
end

-- Send abort, wait briefly for graceful SDK teardown, then SIGKILL the group.
local function kill_helper()
  if not helper then return end
  pcall(function() helper_send({ type = "abort" }) end)
  -- Give the helper time to abortController.abort() so the SDK reaps its child.
  yuke.sleep(200)
  pcall(function() helper.proc:kill() end)
  helper = nil
end

local function spawn_helper(req)
  helper = { proc = yuke.proc.spawn({ "/home/xyaman/.nvm/versions/node/v22.19.0/bin/node", helper_path }, { env = {} }) }
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
    config = config,
  })
  local ready = helper_recv(15000)
  if ready.type ~= "ready" then error("claude-bridge: expected ready, got " .. (ready.type or "?")) end
  saved_session = ready.session_id
  init_model = req.model
end

-- Drain one SDK turn from the helper into `out`. Streams text/reasoning/usage
-- live and buffers tool calls. Returns the stop reason ("tool_calls", "stop",
-- "length", "error") without calling out:done()/out:error() — the caller owns
-- termination so it can replay deferred prompts before closing the stream.
local last_error = nil
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
        local m = helper_recv_optional(200)
        if m == nil then break end
        if m.type == "tool_use" then
          table.insert(tool_calls, { id = m.id, name = m.name, arguments = m.arguments })
        else
          if m.type == "done" then
            if m.usage then out:usage(m.usage) end
            if m.session_id then saved_session = m.session_id end
          end
          break
        end
      end
      for _, tc in ipairs(tool_calls) do out:tool_call(tc) end
      return "tool_calls"
    elseif t == "done" then
      if msg.usage then out:usage(msg.usage) end
      if msg.session_id then saved_session = msg.session_id end
      return msg.stop_reason or "stop"
    elseif t == "error" then
      last_error = msg.message or "unknown error"
      return "error"
    end
  end
end

-- Metadata lives in ~/.yuke/providers.json under "claude-bridge".
-- This file only binds the stream (the turn-driver) to that name.
yuke.stream("claude-bridge", function(req, out)
  local tool_results, trailing_users = split_trailing(req.messages)

  -- Spawn (or respawn) the helper when it's gone, or when the model changed
  -- mid-session (a live helper can't be retargeted via a turn command).
  if helper == nil or (init_model ~= nil and init_model ~= req.model) then
    if helper ~= nil then
      kill_helper()
      saved_session = nil
    end
    spawn_helper(req)
    helper_send({ type = "turn", prompt = trailing_users[1] or "" })
    for i = 2, #trailing_users do table.insert(deferred_prompts, trailing_users[i]) end
  elseif last_stop == "tool_calls" then
    -- Mid-turn: forward pending tool results, defer trailing user messages.
    for _, tr in ipairs(tool_results) do
      helper_send({ type = "tool_result", id = tr.id, content = tr.content })
    end
    for _, u in ipairs(trailing_users) do table.insert(deferred_prompts, u) end
  else
    -- Previous turn ended; start a fresh turn.
    helper_send({ type = "turn", prompt = trailing_users[1] or "" })
    for i = 2, #trailing_users do table.insert(deferred_prompts, trailing_users[i]) end
  end

  -- Drain loop: after each non-tool_calls response, replay deferred prompts
  -- as continuation turns (new SDK query resuming the same CC session).
  -- All responses stream into this one callback invocation; out:done() fires
  -- exactly once at the end.
  while true do
    local stop = drain(out)
    last_stop = stop

    if stop == "error" then
      out:error(last_error)
      return
    end

    if stop == "tool_calls" then
      -- Model wants tools; flush tool calls and let the engine execute them.
      -- Deferred prompts stay queued for the next round.
      out:done({ stop_reason = "tool_calls" })
      return
    end

    -- Turn ended (stop/length/etc). Replay deferred user messages as
    -- continuation turns before closing the stream.
    if #deferred_prompts > 0 then
      helper_send({ type = "turn", prompt = table.remove(deferred_prompts, 1) })
    else
      out:done({ stop_reason = stop })
      return
    end
  end
end)

-- Route compaction through the same backend. Passes structured messages (not
-- flattened text) so the summarizer sees tool_use/tool_result shape.
yuke.on("before_compact", function(messages)
  if helper == nil then return nil end
  if last_stop == "tool_calls" then
    -- Helper is mid-turn with a blocked MCP handler; running a summarize query
    -- concurrently would corrupt state. Let the default compactor handle it.
    return nil
  end
  helper_send({ type = "summarize", messages = messages })
  while true do
    local msg = helper_recv()
    if msg.type == "summarize_done" then
      -- Kill the helper so the next round respawns with compacted history.
      -- Keep saved_session: doInit reimports into the same UUID (delete +
      -- recreate), preserving prompt-cache warmth — same as pi's preserveId.
      kill_helper()
      last_stop = nil
      return { summary = msg.text }
    elseif msg.type == "summarize_error" then
      yuke.log("claude-bridge compaction failed: " .. (msg.message or "?"), "warn")
      return nil
    end
  end
end)

-- Clear deferred state at the start of each run.
yuke.on("agent_start", function()
  deferred_prompts = {}
end)

-- Tear down at run end. On cancel/error, kill the helper and drop the saved
-- session so the next round respawns from scratch. On a clean completion, keep
-- the helper alive for prompt-cache warmth across turns.
yuke.on("agent_end", function(outcome)
  if outcome ~= "completed" then
    kill_helper()
    saved_session = nil
    last_stop = nil
  end
end)

return M
