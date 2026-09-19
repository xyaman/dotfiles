import { tools, exec, env } from "yuke";

const API = "https://api.monid.ai";
const DONE = new Set(["COMPLETED", "FAILED", "BLOCKED", "STOPPED", "TIMED_OUT"]);
const SNIPPET = 140;
const TITLE = 140;
const PAGE = 4000;
const RESULTS = 5;

function clip(text, max) {
  const compact = String(text).replace(/\s+/g, " ").trim();
  if (compact.length <= max) return compact;
  return compact.slice(0, max).replace(/\s+\S*$/, "") + "…";
}

function lines(...parts) {
  return parts.filter(Boolean).join("\n");
}

function quote(value) {
  return "'" + String(value).replaceAll("'", "'\\''") + "'";
}

async function sleep(ms, signal) {
  if (signal?.aborted) throw new Error("aborted");
  await new Promise((resolve) => setTimeout(resolve, ms));
  if (signal?.aborted) throw new Error("aborted");
}

async function request(url, signal, payload) {
  if (!env.get("MONID_API_KEY")) throw new Error("MONID_API_KEY is not set");

  let command = `curl -sS -H "Authorization: Bearer $MONID_API_KEY"`;
  if (payload !== undefined) {
    command += ` -H "Content-Type: application/json" --data-binary ${quote(JSON.stringify(payload))}`;
  }
  command += ` ${quote(url)}`;

  const result = await exec(command, { timeoutMs: 120000, signal });
  if (result.code !== 0) throw new Error(result.stderr.trim() || "curl failed");
  const text = result.stdout;
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(text.slice(0, 200) || "Monid returned non-JSON");
  }
}

async function run(endpoint, input, signal) {
  let job = await request(`${API}/v1/run`, signal, { provider: "tinyfish", endpoint, input });
  for (let n = 0; n < 30 && job.status && !DONE.has(job.status); n++) {
    const id = job.runId;
    if (typeof id !== "string" || !/^[A-Za-z0-9]+$/.test(id)) throw new Error("Monid run did not start");
    await sleep(2000, signal);
    job = await request(`${API}/v1/runs/${id}`, signal);
  }
  if (job.status && job.status !== "COMPLETED") throw new Error(`Monid ${job.status}`);
  return job.output;
}

function formatSearch(output) {
  const results = output?.results;
  if (!Array.isArray(results) || results.length === 0) return "No results.";

  return results.slice(0, RESULTS).map((hit, i) => {
    const title = clip(hit.title || "(untitled)", TITLE);
    const when = hit.date || hit.year || "";
    const snippet = hit.snippet ? clip(hit.snippet, SNIPPET) : "";
    return lines(`${i + 1}. ${title}${when ? " (" + when + ")" : ""}`, hit.url, snippet);
  }).join("\n\n");
}

function formatFetch(output) {
  const page = output?.results?.[0];
  if (!page) {
    const errors = output?.errors ?? [];
    if (errors.length) return errors.map((err) => err.message || err.code || String(err)).join("\n");
    return "Empty fetch.";
  }

  let text = typeof page.text === "string" ? page.text.replace(/\n{3,}/g, "\n\n").trim() : "";
  if (text.length > PAGE) text = `${text.slice(0, PAGE)}\n\n[truncated]`;
  return lines(page.title, page.final_url || page.url, text);
}

tools.define({
  name: "web_search",
  description: "Live web search. Titles, URLs, short snippets. Use web_fetch for page text.",
  parameters: {
    type: "object",
    properties: {
      query: { type: "string", description: "Search query." },
    },
    required: ["query"],
    additionalProperties: false,
  },
  async execute(args, signal) {
    const query = String(args.query || "").trim();
    if (!query) throw new Error("query is required");
    return formatSearch(await run("/search", { queryParams: { query } }, signal));
  },
});

tools.define({
  name: "web_fetch",
  description: "Fetch a URL as markdown. Long pages are truncated.",
  parameters: {
    type: "object",
    properties: {
      url: { type: "string", description: "http(s) URL." },
    },
    required: ["url"],
    additionalProperties: false,
  },
  async execute(args, signal) {
    const url = String(args.url || "").trim();
    if (!/^https?:\/\//i.test(url)) throw new Error("url must be http(s)");
    return formatFetch(await run("/fetch", { body: { urls: [url], format: "markdown" } }, signal));
  },
});
