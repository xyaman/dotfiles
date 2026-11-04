# Yuke plugins

`~/.config/yuke` is symlinked to this directory. `config.json` loads the managed
`btw` plugin and the local `herdr` and `web` plugins. Local plugins use the
`apply` / `session` API of `lostcoords/yuke`.

## Web

Export `MONID_API_KEY` in the shell that starts yuke. The plugin reads the process
environment; it does not load an `.env` file.

- `web_search({ query })`: TinyFish `/free/search` through Monid.
- `web_fetch({ url })`: TinyFish `/free/fetch`, requesting Markdown.

Both tools run concurrently (`concurrency: "parallel"`). Each tool returns at most
50 KiB of UTF-8 text, including its truncation notice. This matches the output
budget of yuke's built-in `read` / `exec` tools. A response within the budget stays
as complete compact JSON. An oversized response becomes a text prefix with a notice
and an absolute path to the full output. Use `read` or `exec` to inspect that file.
The file stays in the web plugin's data directory across reloads. Provider-side
limits still apply. The cap limits model context, not network response size.

Free quotas through Monid (not TinyFish direct-account allowances):

| Tool | Per minute | Other limit |
| --- | --- | --- |
| Search | 30 searches | 500/hour |
| Fetch | 150 fetched URLs | 1,000/day |

Rate limits and provider errors are returned as tool errors. There is **no paid
fallback** to `/search` or `/fetch`. Requests honor cancellation and have a
150-second overall deadline, including asynchronous polling. This follows
TinyFish's recommendation to allow time for its 110-second backend timeout and
120-second CDN ceiling.

Error handling distinguishes Monid run status, provider HTTP status, and fetch
per-URL errors (which can arrive with HTTP 200). Fetch failures retain
`errors[]` objects, including `error`, `status`, URL, and any retry hints. Empty
search results are valid; a fetch with no successful result is an error. HTTP error
bodies include `Retry-After` when Monid returns it. Oversized errors use the same
50 KiB cap and full-output files as successful responses. The tools have no
automatic web retries or paid fallbacks.

Search uses `input.queryParams.query`; fetch uses
`input.body: { urls: [url], format: "markdown" }` in Monid's `POST /v1/run` envelope.
Fetch leaves `ttl` unset, accepting TinyFish's default cache behavior; full output
does not guarantee a fresh origin fetch.

References:
- [TinyFish Search](https://docs.tinyfish.ai/search-api/reference)
- [TinyFish Fetch](https://docs.tinyfish.ai/fetch-api/reference)
- [Monid Run](https://monid.ai/docs/api/run)
- [Monid Get Run](https://monid.ai/docs/api/runs/get)

## Herdr

The reporter runs only in the TUI, with `HERDR_ENV=1`, `HERDR_SOCKET_PATH`, and
`HERDR_PANE_ID` set by Herdr. It skips nested agents identified by `AI_AGENT` or
`CLAUDECODE`.

It aggregates open sessions: an unanswered interaction reports `blocked`, otherwise
a running turn reports `working`, otherwise `idle`. Socket reports are serialized,
bounded to 250 ms, and retried at most three times per state change. Cleanup
releases the `custom:yuke` label without blocking on a missing daemon.

## Checks

From this directory, using the installed yuke SDK referenced by `tsconfig.json`:

```sh
tsc -p tsconfig.json
MONID_API_KEY=test yuke test plugins/web plugins/herdr
yuke plugin list
```

The tests mock HTTP and use temporary Unix sockets; they make no paid or live web
requests. Restart yuke or reload its profile to load changed plugin code.
