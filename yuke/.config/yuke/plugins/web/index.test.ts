import { readTextFile } from "yuke:fs";
import { assert, createHost, equal, test } from "yuke:test";

const folder = import.meta.dirname!;

function mockFetch(responses: unknown[]): { calls: { url: string; body: unknown }[]; restore: () => void } {
  const original = globalThis.fetch;
  const calls: { url: string; body: unknown }[] = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), body: init?.body ? JSON.parse(String(init.body)) : undefined });
    assert(responses.length > 0, "unexpected request");
    const response = responses.shift();
    return response instanceof Response ? response : Response.json(response);
  };
  return { calls, restore: () => { globalThis.fetch = original; } };
}

async function savedText(text: string): Promise<string> {
  assert(new TextEncoder().encode(text).length <= 51_200, "tool output exceeds 50 KiB");
  const notice = /\n\[web output truncated\. Full output: (.+)\. Use read or exec to inspect it\.\]$/.exec(text);
  assert(notice?.[1], "truncation must name the full-output file");
  const full = await readTextFile(notice[1], { fatal: true });
  assert(full.startsWith(text.slice(0, notice.index)), "the preview must be a UTF-8 prefix of the full output");
  return full;
}

function completed(output: unknown): unknown {
  return { status: "COMPLETED", providerResponse: { httpStatus: 200 }, output };
}

test("search caps large results and saves every result and metadata", async () => {
  const output = {
    results: Array.from({ length: 20 }, (_, i) => ({
      title: `${i}: ${"title ".repeat(100)}`,
      url: `https://example.com/${i}`,
      snippet: "full snippet\n".repeat(300),
      extra: { authors: ["Author"], year: 2026 },
    })),
    metadata: { total: 100 },
  };
  const mock = mockFetch([completed(output)]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const result = await session.call("web_search", { query: "  test query  " });
    equal(result.isError, false);
    equal(await savedText(result.text), JSON.stringify(output));
    equal(result.display, [{ kind: "markdown", text: "20 results (example.com)" }]);
    equal(mock.calls, [{ url: "https://api.monid.ai/v1/run", body: {
      provider: "tinyfish", endpoint: "/free/search", input: { queryParams: { query: "test query" } },
    } }]);
  } finally { mock.restore(); }
});

test("fetch caps large Markdown and saves whitespace, links, and metadata", async () => {
  const output = { results: [{
    title: "Example", url: "https://example.com/", text: "# Heading\n\n\n  indented 日本語\n".repeat(5000),
    links: ["https://example.com/link"], extra: "keep me",
  }], errors: [] };
  const mock = mockFetch([completed(output)]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const result = await session.call("web_fetch", { url: "https://example.com/" });
    equal(result.isError, false);
    equal(await savedText(result.text), JSON.stringify(output));
    equal(mock.calls[0]?.body, {
      provider: "tinyfish", endpoint: "/free/fetch",
      input: { body: { urls: ["https://example.com/"], format: "markdown" } },
    });
  } finally { mock.restore(); }
});

test("invalid input makes no request", async () => {
  const mock = mockFetch([]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    equal((await session.call("web_search", { query: "  " })).isError, true);
    equal((await session.call("web_fetch", { url: "file:///etc/passwd" })).isError, true);
    equal(mock.calls.length, 0);
  } finally { mock.restore(); }
});

test("rate limits and page failures are errors, never a paid fallback", async () => {
  const mock = mockFetch([
    new Response("Free quota exceeded", { status: 429 }),
    completed({ results: [], errors: [{ url: "https://example.com/", error: "bot_blocked" }] }),
    { status: "COMPLETED", providerResponse: { httpStatus: 429 }, output: null },
    { status: "BLOCKED", reason: "Quota exceeded" },
  ]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const limited = await session.call("web_search", { query: "test" });
    assert(limited.isError && limited.text.includes("429"));
    const blocked = await session.call("web_fetch", { url: "https://example.com/" });
    assert(blocked.isError && blocked.text.includes("bot_blocked"));
    const provider = await session.call("web_search", { query: "test" });
    assert(provider.isError && provider.text.includes("429"));
    const quota = await session.call("web_search", { query: "test" });
    assert(quota.isError && quota.text.includes("Quota exceeded"));
    equal(mock.calls.length, 4);
    assert(mock.calls.every(call => JSON.stringify(call.body).includes('"/free/')));
  } finally { mock.restore(); }
});

test("asynchronous runs are polled for the complete output", async () => {
  const output = { results: [{ title: "Async", url: "https://example.com/" }] };
  const mock = mockFetch([{ status: "READY", runId: "ABC123" }, completed(output)]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const result = await session.call("web_search", { query: "async" });
    equal(result.isError, false);
    equal(result.text, JSON.stringify(output));
    equal(JSON.parse(result.text), output);
    equal(mock.calls[1]?.url, "https://api.monid.ai/v1/runs/ABC123");
  } finally { mock.restore(); }
});

test("search and fetch execute concurrently in one model response", async () => {
  const original = globalThis.fetch;
  const endpoints: string[] = [];
  let release: (() => void) | undefined;
  const bothStarted = new Promise<void>(resolve => { release = resolve; });
  globalThis.fetch = async (_, init) => {
    const body = JSON.parse(String(init?.body));
    endpoints.push(body.endpoint);
    if (endpoints.length === 2) release!();
    await bothStarted;
    return Response.json(completed({ results: [{ title: "Complete", text: "Full page" }] }));
  };
  try {
    const { reply } = await import("yuke:test");
    await using host = await createHost({
      plugins: [{ folder }],
      replies: [reply.toolCalls([
        { name: "web_search", args: { query: "test" } },
        { name: "web_fetch", args: { url: "https://example.com/" } },
      ]), reply.text("done")],
    });
    const session = await host.openSession();
    await session.send("search and fetch");
    equal(endpoints.sort(), ["/free/fetch", "/free/search"]);
  } finally { globalThis.fetch = original; }
});

test("cancellation stops polling promptly", async () => {
  const mock = mockFetch([{ status: "RUNNING", runId: "ABC123" }]);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 20);
  try {
    const { rejects } = await import("yuke:test");
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    await rejects(session.call("web_search", { query: "cancel" }, { signal: controller.signal }));
    equal(mock.calls.length, 1);
  } finally { clearTimeout(timer); mock.restore(); }
});

test("fetch HTTP 200 errors preserve TinyFish error codes, status, URL, and retry hints", async () => {
  const outputs = [
    { results: [], errors: [{ url: "https://example.com/missing", error: "page_not_found", status: 404 }], request_id: "request-404" },
    { results: [], errors: [{ url: "https://example.com/", error: "selector_not_matched", unmatched_selectors: [".missing"], candidate_selectors: ["main", "article"] }] },
    { results: [], errors: [{ url: "https://example.com/", error: "timeout" }] },
    { results: [], errors: [] },
  ];
  const mock = mockFetch(outputs.map(completed));
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    for (const output of outputs) {
      const result = await session.call("web_fetch", { url: "https://example.com/" });
      equal(result.isError, true);
      equal(result.text, JSON.stringify(output));
    }
  } finally { mock.restore(); }
});

test("empty search results are a successful response", async () => {
  const output = { query: "no matches", results: [], total_results: 0, page: 0 };
  const mock = mockFetch([completed(output)]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const result = await session.call("web_search", { query: "no matches" });
    equal(result.isError, false);
    equal(result.text, JSON.stringify(output));
    equal(result.display, [{ kind: "markdown", text: "No results" }]);
  } finally { mock.restore(); }
});

test("HTTP errors preserve complete details and Retry-After without retrying", async () => {
  const error = { error: { code: "RATE_LIMIT_EXCEEDED", message: "quota detail ".repeat(100) }, request_id: "rate-request" };
  const mock = mockFetch([new Response(JSON.stringify(error), { status: 429, headers: { "Retry-After": "60" } })]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const result = await session.call("web_search", { query: "test" });
    assert(result.isError);
    assert(result.text.includes("HTTP 429"));
    assert(result.text.includes("Retry-After: 60"));
    assert(result.text.includes(JSON.stringify(error)));
    equal(mock.calls.length, 1);
  } finally { mock.restore(); }
});

test("completed async provider failures preserve the upstream error body", async () => {
  const provider = { httpStatus: 503, error: { error: { code: "SERVICE_UNAVAILABLE", message: "Try later" }, request_id: "provider-request" } };
  const mock = mockFetch([{ status: "READY", runId: "ABC123" }, { status: "COMPLETED", providerResponse: provider, output: null }]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const result = await session.call("web_search", { query: "test" });
    assert(result.isError && result.text.includes("TinyFish HTTP 503"));
    assert(result.text.includes(JSON.stringify(provider)));
    equal(mock.calls.length, 2);
  } finally { mock.restore(); }
});

test("failed, blocked, stopped, and timed-out Monid runs never become successful output", async () => {
  const jobs = ["FAILED", "BLOCKED", "STOPPED", "TIMED_OUT"].map(status => ({ status, reason: `${status} detail`, error: { code: "TEST_ERROR" } }));
  const mock = mockFetch(jobs.slice());
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    for (const job of jobs) {
      const result = await session.call("web_search", { query: "test" });
      assert(result.isError);
      assert(result.text.includes(JSON.stringify(job)));
    }
    equal(mock.calls.length, jobs.length);
  } finally { mock.restore(); }
});

test("malformed JSON, envelopes, outputs, and unknown states are rejected", async () => {
  const responses = [
    new Response("<html>upstream failure</html>"),
    [], null, "unexpected",
    { status: "SURPRISE", runId: "ABC123" },
    { status: "READY", runId: "../invalid" },
    {}, completed(null), completed([]), completed({}), completed({ results: "not an array" }),
    completed({ error: { code: "UPSTREAM_FAILURE" } }),
  ];
  const mock = mockFetch(responses.slice());
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    for (let i = 0; i < responses.length; i++) {
      const result = await session.call("web_search", { query: "test" });
      assert(result.isError, `response ${i} should fail`);
    }
    equal(mock.calls.length, responses.length);
  } finally { mock.restore(); }
});

test("search summarizes unique hosts in result order without changing model content", async () => {
  const output = { results: [
    { url: "https://github.com/first", snippet: "Keep this snippet" },
    { url: "https://docs.rs/package" },
    { url: "https://github.com/second" },
    { url: "https://tokio.rs/" },
    { url: "https://example.com/" },
    { url: "https://rust-lang.org/" },
  ], total_results: 100 };
  const mock = mockFetch([completed(output)]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const result = await session.call("web_search", { query: "Rust async cancellation" });
    equal(result.display, [{ kind: "markdown", text: "6 results (github.com, docs.rs, tokio.rs, +2 more)" }]);
    equal(JSON.parse(result.text), output);
    equal(result.isError, false);
  } finally { mock.restore(); }
});

test("search handles one result and unusable host fields without losing results", async () => {
  const outputs = [
    { results: [{ url: "https://example.com/page" }] },
    { results: [null, {}, { url: "not a URL" }, { url: 42 }, { url: "mailto:hello@example.com" }] },
  ];
  const mock = mockFetch(outputs.map(completed));
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const one = await session.call("web_search", { query: "one" });
    equal(one.display, [{ kind: "markdown", text: "1 result (example.com)" }]);
    const missing = await session.call("web_search", { query: "missing hosts" });
    equal(missing.display, [{ kind: "markdown", text: "5 results" }]);
    equal(JSON.parse(missing.text), outputs[1]);
    equal(missing.isError, false);
  } finally { mock.restore(); }
});

test("fetch reports UTF-8 page bytes rather than characters or JSON size", async () => {
  const outputs = [
    { results: [{ text: "日本語", title: "Metadata is not page content" }] },
    { results: [{ text: "a".repeat(1023) }] },
    { results: [{ text: "é".repeat(512) }] },
    { results: [{ text: "a".repeat(16042) }] },
    { results: [{ text: "a".repeat(1024 * 1024) }] },
    { results: [{ text: "" }] },
  ];
  const expected = [
    "Fetched · 9 B", "Fetched · 1023 B", "Fetched · 1.0 KiB",
    "Fetched · 15.7 KiB", "Fetched · 1.0 MiB", "Fetched · 0 B",
  ];
  const mock = mockFetch(outputs.map(completed));
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    for (const [index, output] of outputs.entries()) {
      const result = await session.call("web_fetch", { url: "https://example.com/" });
      equal(result.display, [{ kind: "markdown", text: expected[index] }]);
      equal(JSON.parse(index === 4 ? await savedText(result.text) : result.text), output);
      equal(result.isError, false);
    }
  } finally { mock.restore(); }
});

test("web calls keep query and URL headers with compact displays in the transcript", async () => {
  const { reply } = await import("yuke:test");
  const mock = mockFetch([
    completed({ results: [{ url: "https://example.com/" }] }),
    completed({ results: [{ text: "Page" }] }),
  ]);
  try {
    await using host = await createHost({
      plugins: [{ folder }],
      replies: [
        reply.toolCall("web_search", { query: "test query" }),
        reply.toolCall("web_fetch", { url: "https://example.com/" }),
        reply.text("done"),
      ],
    });
    const session = await host.openSession();
    await session.send("search and fetch");
    const calls = session.transcript.entries.filter((entry) => entry.kind === "tool");
    equal(calls.map((entry) => [entry.hints, entry.display]), [
      [{ title: "Search", subject: { argument: "query", kind: "text" }, preview: "head" },
        [{ kind: "markdown", text: "1 result (example.com)" }]],
      [{ title: "Fetch", subject: { argument: "url", kind: "uri" }, preview: "head" },
        [{ kind: "markdown", text: "Fetched · 4 B" }]],
    ]);
  } finally { mock.restore(); }
});

test("the 50 KiB boundary keeps exact output and truncates one byte more", async () => {
  const padding = "x".repeat(51_173);
  const mock = mockFetch([
    completed({ results: [], padding }),
    completed({ results: [], padding: `${padding}x` }),
  ]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const exact = await session.call("web_search", { query: "exact" });
    equal(new TextEncoder().encode(exact.text).length, 51_200);
    equal(exact.text, `{"results":[],"padding":"${padding}"}`);
    const over = await session.call("web_search", { query: "over" });
    equal(await savedText(over.text), `{"results":[],"padding":"${padding}x"}`);
  } finally { mock.restore(); }
});

test("large upstream errors and per-page errors stay capped and retain full details on disk", async () => {
  const detail = "quota detail ".repeat(10_000) + "END OF DETAILS";
  const body = `HTTP failure: ${detail}`;
  const page = { results: [], errors: [{ error: "bot_blocked", detail }] };
  const mock = mockFetch([
    new Response(body, { status: 429, headers: { "Retry-After": "60" } }),
    completed(page),
  ]);
  try {
    await using host = await createHost({ plugins: [{ folder }] });
    const session = await host.openSession();
    const upstream = await session.call("web_search", { query: "error" });
    equal(upstream.isError, true);
    equal(await savedText(upstream.text), `Monid HTTP 429 (Retry-After: 60): ${body}`);
    const blocked = await session.call("web_fetch", { url: "https://example.com/" });
    equal(blocked.isError, true);
    equal(await savedText(blocked.text), JSON.stringify(page));
  } finally { mock.restore(); }
});

test("parallel large web results enter model context only as bounded previews", async () => {
  const { reply } = await import("yuke:test");
  const mock = mockFetch([
    completed({ results: [{ snippet: "search ".repeat(20_000) }], marker: "search-end" }),
    completed({ results: [{ text: "page ".repeat(500_000) }], marker: "fetch-end" }),
  ]);
  try {
    await using host = await createHost({
      plugins: [{ folder }],
      replies: [reply.toolCalls([
        { name: "web_search", args: { query: "large" } },
        { name: "web_fetch", args: { url: "https://example.com/" } },
      ]), reply.text("done")],
    });
    const session = await host.openSession({ model: { provider: "openai", model: "gpt-4.1" } });
    await session.send("search and fetch");
    const results = host.requests[1]?.messages.filter(message => message.role === "tool");
    assert(results);
    equal(results.length, 2);
    const search = JSON.parse(await savedText(results[0]!.text));
    const fetch = JSON.parse(await savedText(results[1]!.text));
    equal([search.marker, fetch.marker], ["search-end", "fetch-end"]);
    equal([search.results[0].snippet.length, fetch.results[0].text.length], [140_000, 2_500_000]);
  } finally { mock.restore(); }
});
