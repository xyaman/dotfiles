#!/usr/bin/env node
// yuke claude-bridge helper.
//
// Wraps @anthropic-ai/claude-agent-sdk query(). yuke's tools are registered as
// an MCP server so the model calls them; each call is bridged over stdio:
// helper writes {type:"tool_use",...} to stdout, awaits {type:"tool_result",...}
// on stdin. Assistant text/reasoning stream as JSON-lines.

import { query, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

// --- stdio framing: one JSON object per line ---
function send(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

// Pending tool calls awaiting a result from yuke. Keyed by tool_use id.
const pending = new Map();

// --- readline on stdin: dispatch incoming JSON messages ---
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
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }
    handle(msg);
  }
});
process.stdin.on("end", () => process.exit(0));

async function handle(msg) {
  if (msg.type === "init") {
    state.cwd = msg.cwd || process.cwd();
    state.system = msg.system;
    state.model = msg.model;
    state.effort = msg.effort;
    state.tools = msg.tools || [];
    state.extraArgs = msg.extraArgs || {};
    send({ type: "ready" });
  } else if (msg.type === "turn") {
    await runTurn(msg.prompt);
  } else if (msg.type === "tool_result") {
    const resolver = pending.get(msg.id);
    if (resolver) {
      pending.delete(msg.id);
      resolver(msg.content);
    }
  } else if (msg.type === "abort") {
    if (state.controller) state.controller.abort();
  }
}

const state = {
  cwd: process.cwd(),
  system: undefined,
  model: undefined,
  effort: undefined,
  tools: [],
  extraArgs: {},
  controller: null,
};

// Build the MCP server exposing yuke's tools. Each handler writes a tool_use
// to stdout and awaits the matching tool_result on stdin.
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

// Convert a JSON Schema (what yuke sends) into a Zod raw shape (what the SDK wants).
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

// Drive one assistant turn. Streams text/reasoning; terminal on result.
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
        tools: [],               // disable CC built-ins; only MCP tools
        mcpServers: { yuke: buildMcp() },
        permissionMode: "bypassPermissions",
        settingSources: [],
        skills: [],
        persistSession: false,
        abortController: state.controller,
        ...state.extraArgs,
      },
    });

    for await (const msg of q) {
      if (state.controller.signal.aborted) break;
      if (msg.type === "assistant") {
        for (const block of msg.message?.content || []) {
          if (block.type === "text" && block.text) send({ type: "text", delta: block.text });
          else if (block.type === "thinking" && block.thinking) send({ type: "reasoning", delta: block.thinking });
        }
      } else if (msg.type === "result") {
        const usage = msg.usage || {};
        if (msg.subtype === "success") {
          send({ type: "done", stop_reason: mapStop(msg.stop_reason), usage });
        } else {
          send({ type: "error", message: msg.result || `claude: ${msg.subtype}` });
        }
        return;
      }
    }
    send({ type: "done", stop_reason: "stop", usage: {} });
  } catch (err) {
    send({ type: "error", message: err?.message || String(err) });
  } finally {
    state.controller = null;
  }
}

function mapStop(r) {
  switch (r) {
    case "end_turn": return "stop";
    case "max_turns": return "length";
    case "tool_use": return "tool_calls";
    default: return "stop";
  }
}

send({ type: "hello", version: 1 });
