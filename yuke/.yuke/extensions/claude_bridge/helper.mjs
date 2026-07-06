#!/usr/bin/env node
// yuke claude-bridge helper.
//
// Wraps @anthropic-ai/claude-agent-sdk query(). Syncs a CC session from yuke's
// messages via cc-session-io, resumed across runs for prompt-cache warmth.
// yuke's tools are an MCP server; each call bridges over stdio.

import { query, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { createSession, deleteSession, repairToolPairing, getClaudeDir } from "cc-session-io";
import { z } from "zod";

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

// Pending MCP tool calls awaiting a result from yuke. Keyed by tool_use id.
const pending = new Map();

// yuke model name → claude CLI id with maximal context. Add entries here as
// CC's lineup changes; unknown names pass through verbatim.
const MODEL_IDS = {
  "opus-4.8":  "claude-opus-4-8[1m]",
  "sonnet-5":  "claude-sonnet-5",
  "haiku-4.5": "claude-haiku-4-5",
};

function sdkModelId(name) {
  return MODEL_IDS[name] ?? name;
}

const state = {
  cwd: process.cwd(),
  system: undefined,
  model: undefined,
  effort: undefined,
  tools: [],
  sessionId: null,
  cursor: 0,
  projectPath: null,
  turnController: null,
  summarizeController: null,
  config: {
    claude_path: null,
    system_prompt_mode: "replace",
    setting_sources: [],
    skills: [],
    strict_mcp_config: true,
    include_partial_messages: true,
    thinking_display: "summarized",
  },
};

// --- stdio readline ---
let buf = "";
process.stdin.setEncoding("utf8");
// Catch throws in handle() so the helper survives bugs and the Lua side gets a
// real error event instead of an opaque EOF.
process.stdin.on("data", (chunk) => {
  buf += chunk;
  let nl;
  while ((nl = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;
    try {
      const msg = JSON.parse(line);
      handle(msg).catch((e) => send({ type: "error", message: "handle: " + (e?.message || String(e)) }));
    } catch { continue; }
  }
});
process.stdin.on("end", () => process.exit(0));
process.stdin.on("error", (e) => send({ type: "error", message: "stdin: " + (e?.message || String(e)) }));

async function handle(msg) {
  switch (msg.type) {
    case "init": return doInit(msg);
    case "turn": return runTurn(msg);
    case "summarize": return runSummarize(msg);
    case "cursor": setCursor(msg.cursor); return;
    case "tool_result": {
      const r = pending.get(msg.id);
      if (r) { pending.delete(msg.id); r(msg.content); }
      return;
    }
    case "abort": teardown(); return;
  }
}

function doInit(msg) {
  state.cwd = msg.cwd || process.cwd();
  state.system = msg.system;
  state.model = msg.model;
  state.effort = msg.effort;
  state.tools = msg.tools || [];
  state.projectPath = msg.projectPath || state.cwd;
  if (msg.config) Object.assign(state.config, msg.config);
  mcpServer = null; // tool set may have changed; rebuild on next buildMcp().
  state.sessionId = msg.session_id || null;
  state.cursor = 0;
  send({ type: "ready", session_id: state.sessionId });
}

function setCursor(cursor) {
  const n = Number(cursor);
  if (Number.isFinite(n) && n >= 0) state.cursor = Math.max(state.cursor, Math.floor(n));
}

function syncSessionForTurn(messages) {
  if (!Array.isArray(messages) || messages.length === 0) return state.sessionId;

  const prior = messages.slice(0, -1);
  if (state.sessionId && prior.length >= state.cursor) {
    const missed = prior.slice(state.cursor);
    const assistantOnly = missed.length > 0 && missed.every((m) => m?.role === "assistant");
    if (missed.length === 0 || assistantOnly) {
      if (assistantOnly) state.cursor = prior.length;
      return state.sessionId;
    }
  }

  if (prior.length === 0) {
    state.sessionId = null;
    state.cursor = 0;
    return null;
  }

  const claudeDir = getClaudeDir(process.env.CLAUDE_CONFIG_DIR);
  const previousSessionId = state.sessionId;
  if (previousSessionId) {
    try { deleteSession(previousSessionId, state.projectPath, claudeDir); } catch {}
  }
  const session = createSession({
    projectPath: state.projectPath,
    ...(previousSessionId ? { sessionId: previousSessionId } : {}),
    cwd: state.cwd,
    claudeDir,
  });
  const converted = repairToolPairing(convertMessages(prior));
  if (converted.length > 0) session.importMessages(converted);
  session.save();
  state.sessionId = session.sessionId;
  state.cursor = prior.length;
  return state.sessionId;
}

// --- yuke message -> cc-session-io Message (Anthropic shape) ---

// Sanitize tool ids: Anthropic requires [a-zA-Z0-9_-] only.
const sanitizeCache = new Map();
function sanitizeToolId(id) {
  const cached = sanitizeCache.get(id);
  if (cached) return cached;
  const clean = String(id).replace(/[^a-zA-Z0-9_-]/g, "_");
  sanitizeCache.set(id, clean);
  return clean;
}

function convertMessages(messages) {
  const out = [];
  for (const m of messages) {
    if (m.role === "system") continue;
    if (m.role === "user") {
      out.push({ role: "user", content: toUserContent(m.content) });
    } else if (m.role === "assistant") {
      out.push({ role: "assistant", content: toAssistantBlocks(m) });
    } else if (m.role === "tool") {
      const text = typeof m.content === "string" ? m.content : partsToText(m.content);
      out.push({ role: "user", content: [{
        type: "tool_result",
        tool_use_id: sanitizeToolId(m.tool_call_id),
        content: text || "",
        is_error: !!m.is_error,
      }] });
    }
  }
  return out;
}

function toUserContent(content) {
  if (typeof content === "string") return content || "[empty]";
  if (!Array.isArray(content)) return "[empty]";
  const blocks = [];
  for (const p of content) {
    if (p.type === "text" && p.text) blocks.push({ type: "text", text: p.text });
    else if (p.type === "image" && p.data)
      blocks.push({ type: "image", source: { type: "base64", media_type: p.mime || "image/png", data: p.data } });
  }
  return blocks.length ? blocks : "[empty]";
}

function toAssistantBlocks(m) {
  const blocks = [];
  const text = typeof m.content === "string" ? m.content : partsToText(m.content);
  if (text) blocks.push({ type: "text", text });
  if (m.reasoning_content && m.reasoning_signature)
    blocks.push({ type: "thinking", thinking: m.reasoning_content, signature: m.reasoning_signature });
  for (const tc of m.tool_calls || []) {
    let input;
    try { input = JSON.parse(tc.arguments || "{}"); } catch { input = {}; }
    blocks.push({ type: "tool_use", id: sanitizeToolId(tc.id), name: tc.name, input });
  }
  return blocks.length ? blocks : [{ type: "text", text: "[empty]" }];
}

function partsToText(content) {
  if (!Array.isArray(content)) return "";
  return content.filter((p) => p.type === "text" && p.text).map((p) => p.text).join("\n");
}

// Build the MCP server exposing yuke's tools. Cached after init — handlers are
// stateless (mint fresh ids at call time, key off the module-level pending map).
let mcpServer = null;

function buildMcp() {
  if (mcpServer) return mcpServer;
  const defs = state.tools.map((t) => ({
    name: t.name,
    description: t.description || "",
    inputSchema: jsonSchemaToZod(t.parameters),
    handler: async (args) => {
      const id = "tu_" + Math.random().toString(36).slice(2, 12);
      send({ type: "tool_use", id, name: t.name, arguments: args });
      const content = await new Promise((resolve) => pending.set(id, resolve));
      return { content: [{ type: "text", text: typeof content === "string" ? content : JSON.stringify(content) }] };
    },
  }));
  mcpServer = createSdkMcpServer({ name: "yuke", tools: defs, alwaysLoad: true });
  return mcpServer;
}

function jsonSchemaToZod(schema) {
  const shape = {};
  const props = (schema && schema.properties) || {};
  const required = new Set((schema && schema.required) || []);
  for (const [key, def] of Object.entries(props)) {
    let zod;
    switch (def.type) {
      case "string": zod = z.string(); break;
      case "number": zod = z.number(); break;
      case "integer": zod = z.number().int(); break;
      case "boolean": zod = z.boolean(); break;
      default: zod = z.any();
    }
    shape[key] = required.has(key) ? zod : zod.optional();
  }
  return shape;
}

// Resolve systemPrompt shape from config.system_prompt_mode.
function resolveSystemPrompt() {
  const mode = state.config.system_prompt_mode;
  if (mode === "preset") {
    return { type: "preset", preset: "claude_code", append: state.system || undefined };
  }
  if (mode === "none") return "";
  return state.system || ""; // "replace"
}

// Build extraArgs from config: thinking-display + strict-mcp-config.
function resolveExtraArgs() {
  const args = {};
  if (state.config.thinking_display) args["thinking-display"] = state.config.thinking_display;
  if (state.config.strict_mcp_config) args["strict-mcp-config"] = null;
  return args;
}

// Lua empty tables arrive as {} — coerce to arrays where the SDK expects them.
function asArray(v) {
  if (Array.isArray(v)) return v;
  return [];
}

async function runTurn(msg) {
  const prompt = msg.prompt ?? "";
  const resumeId = syncSessionForTurn(msg.messages);
  const consumedCursor = Number.isFinite(Number(msg.cursor)) ? Math.floor(Number(msg.cursor)) : null;
  state.turnController = new AbortController();
  try {
    const q = query({
      prompt,
      options: {
        cwd: state.cwd,
        env: { ...process.env, ENABLE_CLAUDEAI_MCP_SERVERS: "0", DISABLE_AUTO_COMPACT: "1" },
        model: sdkModelId(state.model),
        systemPrompt: resolveSystemPrompt(),
        effort: state.effort,
        tools: [],
        mcpServers: { yuke: buildMcp() },
        permissionMode: "bypassPermissions",
        settingSources: asArray(state.config.setting_sources),
        skills: asArray(state.config.skills),
        ...(resumeId ? { resume: resumeId } : {}),
        abortController: state.turnController,
        includePartialMessages: state.config.include_partial_messages,
        extraArgs: resolveExtraArgs(),
        ...(state.config.claude_path ? { pathToClaudeCodeExecutable: state.config.claude_path } : {}),
      },
    });
    const ok = await pump(q, state.turnController);
    if (ok && consumedCursor !== null) setCursor(consumedCursor);
  } catch (err) {
    send({ type: "error", message: err?.message || String(err) });
  } finally {
    state.turnController = null;
  }
}

// Summarizer for before_compact: separate controller, real system prompt,
// structured message conversion instead of flat text.
async function runSummarize(msg) {
  state.summarizeController = new AbortController();
  try {
    const messages = repairToolPairing(convertMessages(msg.messages || []));
    const prompt = buildSummaryPrompt(messages);
    const q = query({
      prompt,
      options: {
        cwd: state.cwd,
        env: { ...process.env, ENABLE_CLAUDEAI_MCP_SERVERS: "0", DISABLE_AUTO_COMPACT: "1" },
        model: sdkModelId(state.model),
        systemPrompt: state.system || "You are a helpful assistant.",
        tools: [],
        permissionMode: "bypassPermissions",
        settingSources: [],
        skills: [],
        persistSession: false,
        maxTurns: 1,
        abortController: state.summarizeController,
      },
    });
    let text = "";
    for await (const m of q) {
      if (state.summarizeController.signal.aborted) break;
      if (m.type === "assistant") {
        for (const b of m.message?.content || []) if (b.type === "text" && b.text) text += b.text;
      } else if (m.type === "result") {
        if (m.subtype !== "success") { send({ type: "summarize_error", message: m.result || m.subtype }); return; }
        send({ type: "summarize_done", text: text || m.result || "" });
        return;
      }
    }
    send({ type: "summarize_done", text });
  } catch (err) {
    send({ type: "summarize_error", message: err?.message || String(err) });
  } finally {
    state.summarizeController = null;
  }
}

// Build a structured prompt preserving tool_use/tool_result shape.
function buildSummaryPrompt(messages) {
  return "Summarize the conversation concisely, preserving key decisions, file paths, and important context:\n\n" +
    messages.map((m) => {
      if (typeof m.content === "string") return `${m.role}: ${m.content}`;
      const parts = m.content.map((b) => {
        if (b.type === "text") return b.text;
        if (b.type === "tool_use") return `[calling ${b.name}(${JSON.stringify(b.input)})]`;
        if (b.type === "tool_result") return `[result: ${typeof b.content === "string" ? b.content : JSON.stringify(b.content)}]`;
        if (b.type === "thinking") return "";
        return "";
      }).filter(Boolean);
      return `${m.role}:\n${parts.join("\n")}`;
    }).join("\n\n");
}

// SDK usage → yuke's Usage struct (snake_case → yuke field names).
function mapUsage(u) {
  if (!u) return {};
  const input = (u.input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0);
  const output = u.output_tokens ?? 0;
  const cacheRead = u.cache_read_input_tokens ?? 0;
  return {
    input,
    output,
    cache_read: cacheRead,
    total: input + output,
  };
}

// Stream query events to stdout.
async function pump(q, controller) {
  for await (const msg of q) {
    if (controller.signal.aborted) break;
    if (msg.type === "system" && msg.subtype === "init" && msg.session_id) {
      state.sessionId = msg.session_id;
    } else if (msg.type === "assistant") {
      for (const b of msg.message?.content || []) {
        if (b.type === "text" && b.text) send({ type: "text", delta: b.text });
        else if (b.type === "thinking" && b.thinking) send({ type: "reasoning", delta: b.thinking });
      }
    } else if (msg.type === "result") {
      if (msg.subtype === "success") {
        send({ type: "done", stop_reason: mapStop(msg.stop_reason), usage: mapUsage(msg.usage), session_id: state.sessionId });
        return true;
      } else {
        const detail = msg.errors?.length ? msg.errors.join("; ") : (msg.result || `claude: ${msg.subtype}`);
        send({ type: "error", message: detail });
        return false;
      }
    }
  }
  send({ type: "done", stop_reason: "stop", usage: {}, session_id: state.sessionId });
  return true;
}

function mapStop(r) {
  return ({ end_turn: "stop", max_turns: "length", tool_use: "tool_calls" })[r] || "stop";
}

send({ type: "hello", version: 3 });

// On clean shutdown (stdin closed), abort active queries so the SDK reaps its
// `claude` subprocess. yuke's SIGKILL cancel path is not catchable.
function teardown() {
  if (state.turnController) state.turnController.abort();
  if (state.summarizeController) state.summarizeController.abort();
}
process.on("exit", teardown);
