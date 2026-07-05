#!/usr/bin/env node
// yuke claude-bridge helper.
//
// Wraps @anthropic-ai/claude-agent-sdk query(). Maintains a CC session on disk
// via cc-session-io, synced from yuke's messages each agent run, so resume keeps
// CC's prompt cache warm. yuke's tools are an MCP server; each call is bridged
// over stdio (tool_use out, tool_result in).

import { query, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { createSession, deleteSession } from "cc-session-io";
import { z } from "zod";

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

// Pending MCP tool calls awaiting a result from yuke. Keyed by tool_use id.
const pending = new Map();

// Session state, set on init.
const state = {
  cwd: process.cwd(),
  system: undefined,
  model: undefined,
  effort: undefined,
  tools: [],
  extraArgs: {},
  sessionId: null,
  projectPath: null,
  controller: null,
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
    case "summarize": return runSummarize(msg.prompt);
    case "tool_result": {
      const r = pending.get(msg.id);
      if (r) { pending.delete(msg.id); r(msg.content); }
      return;
    }
    case "abort":
      if (state.controller) state.controller.abort();
      return;
  }
}

// Sync a CC session from yuke's message history, then signal ready.
function doInit(msg) {
  state.cwd = msg.cwd || process.cwd();
  state.system = msg.system;
  state.model = msg.model;
  state.effort = msg.effort;
  state.tools = msg.tools || [];
  state.extraArgs = msg.extraArgs || {};
  state.projectPath = msg.projectPath || state.cwd;

  // Import everything EXCEPT the last message (the new user turn drives query()).
  const all = msg.messages || [];
  const history = all.slice(0, -1);
  const converted = convertMessages(history);

  // Only sync+resume when there's prior history. On the first turn there's
  // nothing to import, so let CC create its own session and capture the id.
  if (converted.length > 0 && msg.session_id) {
    try { deleteSession(msg.session_id, state.projectPath); } catch {}
    const session = createSession({ projectPath: state.projectPath, sessionId: msg.session_id, cwd: state.cwd });
    session.importMessages(converted);
    session.save();
    state.sessionId = session.sessionId;
  } else {
    state.sessionId = null;
  }
  send({ type: "ready", session_id: state.sessionId });
}

// --- yuke message -> cc-session-io Message (Anthropic shape) ---
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
      out.push({ role: "user", content: [{ type: "tool_result", tool_use_id: m.tool_call_id, content: text || "" }] });
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
    else if (p.type === "image" && p.data) blocks.push({ type: "image", source: { type: "base64", media_type: p.mime || "image/png", data: p.data } });
  }
  return blocks.length ? blocks : "[empty]";
}

function toAssistantBlocks(m) {
  const blocks = [];
  const text = typeof m.content === "string" ? m.content : partsToText(m.content);
  if (text) blocks.push({ type: "text", text });
  if (m.reasoning_content && m.reasoning_signature) {
    blocks.push({ type: "thinking", thinking: m.reasoning_content, signature: m.reasoning_signature });
  }
  for (const tc of m.tool_calls || []) {
    let input;
    try { input = JSON.parse(tc.arguments || "{}"); } catch { input = {}; }
    blocks.push({ type: "tool_use", id: tc.id, name: tc.name, input });
  }
  return blocks.length ? blocks : [{ type: "text", text: "[empty]" }];
}

function partsToText(content) {
  if (!Array.isArray(content)) return "";
  const parts = [];
  for (const p of content) if (p.type === "text" && p.text) parts.push(p.text);
  return parts.join("\n");
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
  state.controller = new AbortController();
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
        abortController: state.controller,
        ...state.extraArgs,
      },
    });
    await pump(q);
  } catch (err) {
    send({ type: "error", message: err?.message || String(err) });
  } finally {
    state.controller = null;
  }
}

// Isolated summarizer for before_compact: no tools, one turn, return text.
async function runSummarize(prompt) {
  state.controller = new AbortController();
  try {
    const q = query({
      prompt,
      options: {
        cwd: state.cwd,
        model: state.model,
        systemPrompt: "Summarize the conversation concisely, preserving key decisions and context.",
        tools: [],
        permissionMode: "bypassPermissions",
        settingSources: [],
        skills: [],
        persistSession: false,
        maxTurns: 1,
        abortController: state.controller,
      },
    });
    let text = "";
    for await (const msg of q) {
      if (state.controller.signal.aborted) break;
      if (msg.type === "assistant") {
        for (const b of msg.message?.content || []) if (b.type === "text" && b.text) text += b.text;
      } else if (msg.type === "result") {
        if (msg.subtype !== "success") { send({ type: "summarize_error", message: msg.result || msg.subtype }); return; }
        send({ type: "summarize_done", text: text || msg.result || "" });
        return;
      }
    }
    send({ type: "summarize_done", text });
  } catch (err) {
    send({ type: "summarize_error", message: err?.message || String(err) });
  } finally {
    state.controller = null;
  }
}

// Stream query events to stdout. tool_use ends the round.
async function pump(q) {
  for await (const msg of q) {
    if (state.controller.signal.aborted) break;
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

function randomUuid() {
  // RFC 4122 v4: 8-4-4-4-12, version nibble 4, variant bits.
  const h = "0123456789abcdef";
  let s = "";
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) s += "-";
    else if (i === 14) s += "4";
    else if (i === 19) s += h[(Math.random() * 4) | 8];
    else s += h[(Math.random() * 16) | 0];
  }
  return s;
}

send({ type: "hello", version: 2 });
