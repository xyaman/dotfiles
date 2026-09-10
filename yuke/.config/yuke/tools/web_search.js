import { exec } from "yuke:exec";

const BRAVE_URL = "https://api.search.brave.com/res/v1/web/search";
const TAVILY_URL = "https://api.tavily.com/search";
const REQUEST_TIMEOUT_MS = 20000;
const MAX_QUERY_CHARS = 400;
const MAX_TITLE_CHARS = 160;
const MAX_URL_CHARS = 2048;
const MAX_SNIPPET_CHARS = 360;
const MAX_OUTPUT_CHARS = 4096;

function shellQuote(value) {
  return "'" + String(value).replaceAll("'", "'\\''") + "'";
}

function keyPrelude(name) {
  return [
    "key=\"\"",
    'config_home=${XDG_CONFIG_HOME:-$HOME/.config}',
    'env_file="$config_home/yuke/.env"',
    'if [ -r "$env_file" ]; then',
    `  key=$(sed -n 's/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*//p' "$env_file" | head -n 1 | sed -e 's/^\"//' -e 's/\"$//' -e "s/^'//" -e "s/'$//")`,
    "fi",
    `key=\${key:-\$${name}}`,
    '[ -n "$key" ] || exit 2',
  ].join("\n");
}

async function curl(command, signal) {
  const result = await exec(command, { timeoutMs: REQUEST_TIMEOUT_MS, signal });
  if (result.code !== 0 || result.signal !== null || result.timedOut || result.stdoutDropped !== 0) return null;
  return result.stdout;
}

function compactText(value, limit) {
  if (typeof value !== "string") return "";
  const text = value.slice(0, limit * 4).replace(/\s+/g, " ").trim();
  if (text.length <= limit) return text;

  let end = limit - 1;
  if (end > 0 && text.charCodeAt(end - 1) >= 0xd800 && text.charCodeAt(end - 1) <= 0xdbff) end -= 1;
  return text.slice(0, end) + "…";
}

function compactResults(items, snippetField) {
  const results = [];
  const urls = new Set();
  for (const item of items) {
    if (item === null || typeof item !== "object" || typeof item.url !== "string") continue;
    const url = item.url.trim();
    if (url.length === 0 || url.length > MAX_URL_CHARS || !/^https?:\/\/\S+$/i.test(url) || urls.has(url)) continue;

    urls.add(url);
    results.push({
      title: compactText(item.title, MAX_TITLE_CHARS) || url,
      description: compactText(item[snippetField], MAX_SNIPPET_CHARS),
      url,
    });
  }
  return results;
}

function parseResults(body, container, snippetField) {
  try {
    const data = JSON.parse(body);
    const source = container === null ? data : data[container];
    if (source === null || typeof source !== "object" || !Array.isArray(source.results)) return null;
    return compactResults(source.results, snippetField);
  } catch {
    return null;
  }
}

async function searchBrave(query, maxResults, signal) {
  const command = `${keyPrelude("BRAVE_API_KEY")}
curl --silent --show-error --fail --connect-timeout 5 --max-time 15 -G \\
  -H "X-Subscription-Token: $key" \\
  -H "Accept: application/json" \\
  --data-urlencode ${shellQuote(`q=${query}`)} \\
  --data ${shellQuote(`count=${maxResults}`)} \\
  ${shellQuote(BRAVE_URL)}`;
  const body = await curl(command, signal);
  return body === null ? null : parseResults(body, "web", "description");
}

async function searchTavily(query, maxResults, signal) {
  const queryJson = JSON.stringify(query);
  const command = `${keyPrelude("TAVILY_API_KEY")}
body=$(printf '{"query":%s,"max_results":%d,"search_depth":"basic","include_answer":false,"include_raw_content":false,"include_images":false}' ${shellQuote(queryJson)} ${maxResults})
curl --silent --show-error --fail --connect-timeout 5 --max-time 15 \\
  -H "Authorization: Bearer $key" \\
  -H "Content-Type: application/json" \\
  --data-raw "$body" \\
  ${shellQuote(TAVILY_URL)}`;
  const body = await curl(command, signal);
  return body === null ? null : parseResults(body, null, "content");
}

function formatResults(results) {
  if (results.length === 0) return "No sources found.";

  const lines = ["Sources:"];
  let length = lines[0].length;
  let shown = 0;
  for (const [index, item] of results.entries()) {
    const entry = `${index + 1}. ${item.title} — ${item.url}${item.description === "" ? "" : `\n   ${item.description}`}`;
    if (length + 1 + entry.length > MAX_OUTPUT_CHARS) break;
    lines.push(entry);
    length += 1 + entry.length;
    shown += 1;
  }
  if (shown < results.length) lines.push(`… ${results.length - shown} more source${results.length - shown === 1 ? "" : "s"} omitted.`);
  return lines.join("\n");
}

function parseArgs(args) {
  if (args === null || typeof args !== "object" || Array.isArray(args)) throw new Error("The arguments must be an object.");
  for (const name of Object.keys(args)) if (name !== "query" && name !== "max_results") throw new Error(`Unknown argument: ${name}`);
  if (typeof args.query !== "string") throw new Error("query must be a nonempty string.");
  const query = args.query.trim();
  if (query === "") throw new Error("query must be a nonempty string.");
  if (query.length > MAX_QUERY_CHARS) throw new Error(`query must contain at most ${MAX_QUERY_CHARS} characters.`);

  const maxResults = args.max_results === undefined ? 5 : args.max_results;
  if (typeof maxResults !== "number" || !Number.isSafeInteger(maxResults) || maxResults < 1 || maxResults > 10) {
    throw new Error("max_results must be an integer from 1 to 10.");
  }
  return { query, maxResults };
}

export const webSearchPlugin = {
  name: "web-search",
  apply(ctx) {
    ctx.tools.define({
      name: "web_search",
      description: "Search the web for recent events, library and API versions, and facts that may have changed. Results contain compact title, URL, and snippet sources. Use the current year for recent information.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "The web search query, up to 400 characters." },
          max_results: { type: "integer", minimum: 1, maximum: 10, description: "The number of sources to return. Defaults to 5." },
        },
        required: ["query"],
        additionalProperties: false,
      },
      execute: async (rawArgs, signal) => {
        const { query, maxResults } = parseArgs(rawArgs);
        const brave = await searchBrave(query, maxResults, signal);
        if (brave !== null) return formatResults(brave);

        const tavily = await searchTavily(query, maxResults, signal);
        if (tavily !== null) return formatResults(tavily);
        throw new Error("Both search providers failed. Set BRAVE_API_KEY or TAVILY_API_KEY in ~/.config/yuke/.env or the process environment.");
      },
    });
  },
};
