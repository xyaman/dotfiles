import type { SessionContext } from "yuke:plugins";
import { env } from "yuke:process";

const API = "https://api.monid.ai";
const PENDING = new Set(["READY", "RUNNING", "STOPPING"]);
type Output = Record<string, unknown> & { results: unknown[] };

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

async function sleep(ms: number, signal: AbortSignal): Promise<void> {
  signal.throwIfAborted();
  await new Promise<void>((resolve, reject) => {
    const abort = () => { clearTimeout(timer); reject(signal.reason); };
    const timer = setTimeout(() => { signal.removeEventListener("abort", abort); resolve(); }, ms);
    signal.addEventListener("abort", abort, { once: true });
  });
}

async function request(path: string, key: string, signal: AbortSignal, payload?: unknown): Promise<Record<string, unknown>> {
  const response = await fetch(`${API}${path}`, {
    method: payload === undefined ? "GET" : "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    ...(payload === undefined ? {} : { body: JSON.stringify(payload) }),
    signal,
  });
  const text = await response.text();
  if (!response.ok) {
    const retryAfter = response.headers.get("Retry-After");
    throw new Error(`Monid HTTP ${response.status}${retryAfter ? ` (Retry-After: ${retryAfter})` : ""}: ${text}`);
  }
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new Error(`Monid returned non-JSON: ${text}`);
  }
  if (!isObject(value)) throw new Error(`Invalid Monid response: ${text}`);
  return value;
}

async function run(endpoint: "/free/search" | "/free/fetch", input: unknown, signal: AbortSignal): Promise<Output> {
  const key = env.get("MONID_API_KEY");
  if (!key) throw new Error("MONID_API_KEY is not set");
  const deadline = new AbortController();
  const timer = setTimeout(() => deadline.abort(new Error("Monid request timed out")), 150000);
  const combined = AbortSignal.any([signal, deadline.signal]);
  try {
    let job = await request("/v1/run", key, combined, { provider: "tinyfish", endpoint, input });
    while (typeof job.status === "string" && PENDING.has(job.status)) {
      const id = job.runId;
      if (typeof id !== "string" || !/^[A-Za-z0-9]+$/.test(id)) throw new Error("Monid run did not start");
      await sleep(2000, combined);
      job = await request(`/v1/runs/${id}`, key, combined);
    }
    if (job.status !== "COMPLETED") throw new Error(`Monid ${job.status ?? "invalid response"}: ${JSON.stringify(job)}`);
    const provider = isObject(job.providerResponse) ? job.providerResponse : {};
    const status = provider.httpStatus;
    if (typeof status === "number" && (status < 200 || status >= 300)) {
      throw new Error(`TinyFish HTTP ${status}: ${JSON.stringify(provider)}`);
    }
    if (!isObject(job.output) || !Array.isArray(job.output.results)) {
      throw new Error(`Invalid TinyFish response: ${JSON.stringify(job.output)}`);
    }
    return job.output as Output;
  } finally {
    clearTimeout(timer);
  }
}

export function session(s: SessionContext): void {
  s.tools.define({
    name: "web_search",
    description: "Live web search via TinyFish's free endpoint. Returns all results and metadata without truncation. Use web_fetch for full page text.",
    concurrency: "parallel",
    parameters: {
      type: "object",
      properties: { query: { type: "string", description: "Search query." } },
      required: ["query"],
    },
    hints: { title: "Search", subject: { argument: "query", kind: "text" } },
    async execute(args, context) {
      const query = args.query.trim();
      if (!query) throw new Error("query is required");
      const output = await run("/free/search", { queryParams: { query } }, context.signal);
      const hosts = new Set<string>();
      for (const result of output.results) {
        if (!isObject(result) || typeof result.url !== "string") continue;
        const host = URL.parse(result.url)?.hostname;
        if (host) hosts.add(host);
      }
      const visible = [...hosts].slice(0, 3);
      if (hosts.size > 3) visible.push(`+${hosts.size - 3} more`);
      const count = output.results.length;
      const summary = count === 0 ? "No results" : `${count} result${count === 1 ? "" : "s"}`;
      return {
        text: JSON.stringify(output),
        display: [{ kind: "markdown", text: summary + (visible.length > 0 ? ` (${visible.join(", ")})` : "") }],
      };
    },
  });

  s.tools.define({
    name: "web_fetch",
    description: "Fetch an http(s) URL as Markdown via TinyFish's free endpoint. Returns full page text and metadata without truncation.",
    concurrency: "parallel",
    parameters: {
      type: "object",
      properties: { url: { type: "string", description: "http(s) URL." } },
      required: ["url"],
    },
    hints: { title: "Fetch", subject: { argument: "url", kind: "uri" } },
    async execute(args, context) {
      const parsed = new URL(args.url.trim());
      if (!["http:", "https:"].includes(parsed.protocol)) throw new Error("url must be http(s)");
      const output = await run("/free/fetch", { body: { urls: [parsed.href], format: "markdown" } }, context.signal);
      const text = JSON.stringify(output);
      if (output.results.length === 0) return { text, isError: true };
      const encoder = new TextEncoder();
      let bytes = 0;
      for (const result of output.results) {
        if (isObject(result) && typeof result.text === "string") bytes += encoder.encode(result.text).length;
      }
      const size = bytes < 1024
        ? `${bytes} B`
        : bytes < 1024 * 1024
          ? `${(bytes / 1024).toFixed(1)} KiB`
          : `${(bytes / (1024 * 1024)).toFixed(1)} MiB`;
      return { text, display: [{ kind: "markdown", text: `Fetched · ${size}` }] };
    },
  });
}
