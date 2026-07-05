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

const state = {
  cwd: process.cwd(),
  system: undefined,
  model: undefined,
  effort: undefined,
  tools: [],
  extraArgs: {},
  sessionId: null,
  projectPath: null,
  turnController: null,
  summarizeController: null,
};

// --- stdio readline ---
let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buf += chunk;
  let nl;
  while ((nl = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    handle(msg);
  }
});
process.stdin.on("end", () => process.exit(0));

async function handle(msg) {
  switch (msg.type) {
    case "init": return doInit(msg);
    case "turn": return runTurn(msg.prompt);
    case "summarize": return runSummarize(msg);
    case "tool_result": {
      const r = pending.get(msg.id);
      if (r) { pending.delete(msg.id); r(msg.content); }
      return;
    }
    case "abort":
      if (state.turnController) state.turnController.abort();
      if (state.summarizeController) state.summarizeController.abort();
      return;
  }
}

function doInit(msg) {
  state.cwd = msg.cwd || process.cwd();
  state.system = msg.system;
  state.model = msg.model;
  state.effort = msg.effort;
  state.tools = msg.tools || [];
  state.extraArgs = msg.extraArgs || {};
  state.projectPath = msg.projectPath || state.cwd;
  const claudeDir = getClaudeDir(process.env.CLAUDE_CONFIG_DIR);

  const all = msg.messages || [];
  const history = all.slice(0, -1);
  const converted = repairToolPairing(convertMessages(history));

  // Only sync+resume when there's prior history. First turn: CC creates its own.
  if (converted.length > 0 && msg.session_id) {
    try { deleteSession(msg.session_id, state.projectPath, claudeDir); } catch {}
    const session = createSession({ projectPath: state.projectPath, sessionId: msg.session_id, cwd: state.cwd, claudeDir });
    session.importMessages(converted);
    session.save();
    state.sessionId = session.sessionId;
  } else {
    state.sessionId = null;
  }
  send({ type: "ready", session_id: state.sessionId });
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

// Build the MCP server exposing yuke's tools.
function buildMcp() {
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
  return createSdkMcpServer({ name: "yuke", tools: defs, alwaysLoad: true });
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

async function runTurn(prompt) {
  state.turnController = new AbortController();
  try {
    const q = query({
      prompt,
      options: {
        cwd: state.cwd,
        model: state.model,
        systemPrompt: state.system,
        effort: state.effort,
        tools: [],
        mcpServers: { yuke: buildMcp() },
        permissionMode: "bypassPermissions",
        settingSources: [],
        skills: [],
        resume: state.sessionId,
        abortController: state.turnController,
        ...state.extraArgs,
      },
    });
    await pump(q, state.turnController);
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
        model: state.model,
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
        send({ type: "done", stop_reason: mapStop(msg.stop_reason), usage: msg.usage || {}, session_id: state.sessionId });
      } else {
        const detail = msg.errors?.length ? msg.errors.join("; ") : (msg.result || `claude: ${msg.subtype}`);
        send({ type: "error", message: detail });
      }
      return;
    }
  }
  send({ type: "done", stop_reason: "stop", usage: {}, session_id: state.sessionId });
}

function mapStop(r) {
  return ({ end_turn: "stop", max_turns: "length", tool_use: "tool_calls" })[r] || "stop";
}

send({ type: "hello", version: 3 });
