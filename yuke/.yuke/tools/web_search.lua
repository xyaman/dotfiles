-- Web search tool: Brave Search first, Tavily fallback. Both keys are read
-- from ~/.yuke/.env (BRAVE_API_KEY, TAVILY_API_KEY), falling back to the
-- process environment. Ported from the pi web_search extension at
-- github.com/xyaman/pi-config/extensions/web_search.

local home = yuke.env.get("HOME")

-- Today's date (YYYY-MM-DD) for the tool description, so the model anchors
-- "recent" to the real current year instead of defaulting to older ones. The OS
-- stdlib is dropped from the yuke VM, so this shells out once at load time.
local function today()
	local ok, r = pcall(yuke.exec, "date +%Y-%m-%d")
	if ok and r and r.stdout then
		return (r.stdout:gsub("%s+$", ""))
	end
	return ""
end

-- Percent-encode a query-string value (RFC 3986 unreserved set kept literal).
local function urlencode(s)
	return (tostring(s):gsub("[^%w%-._~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- Parse a simple .env file: skip comments/blank lines, split on first `=`,
-- strip surrounding quotes from the value.
local function parse_env(text)
	local env = {}
	for line in (text or ""):gmatch("[^\r\n]+") do
		local s = line:match("^%s*(.-)%s*$")
		if s ~= "" and s:sub(1, 1) ~= "#" then
			local eq = s:find("=", 1, true)
			if eq then
				local key = s:sub(1, eq - 1):match("^%s*(.-)%s*$")
				local value = s:sub(eq + 1):match("^%s*(.-)%s*$")
				if (value:sub(1, 1) == '"' and value:sub(-1) == '"')
					or (value:sub(1, 1) == "'" and value:sub(-1) == "'")
				then
					value = value:sub(2, -2)
				end
				env[key] = value
			end
		end
	end
	return env
end

-- Load Brave/Tavily keys from ~/.yuke/.env, then the process environment.
local function load_keys()
	local keys = {}
	local path = home and (home .. "/.yuke/.env") or nil
	if path and yuke.fs.exists(path) then
		local ok, text = pcall(yuke.fs.read, path)
		if ok and text then
			local env = parse_env(text)
			keys.brave = env.BRAVE_API_KEY
			keys.tavily = env.TAVILY_API_KEY
		end
	end
	keys.brave = keys.brave or yuke.env.get("BRAVE_API_KEY")
	keys.tavily = keys.tavily or yuke.env.get("TAVILY_API_KEY")
	return keys
end

-- Run a Brave Web Search. Returns nil on any failure so the caller can fall
-- back to Tavily; rethrows only on cancellation (surfaced by yuke.http).
local function search_brave(query, max, key)
	local url = "https://api.search.brave.com/api/v1/web/search?q="
		.. urlencode(query) .. "&count=" .. max
	local ok, res = pcall(yuke.http.get, url, {
		headers = { ["X-Subscription-Token"] = key, ["Accept"] = "application/json" },
		timeout_ms = 15000,
	})
	if not ok or res == nil or res.status ~= 200 then
		return nil
	end
	local ok2, data = pcall(yuke.json.decode, res.body)
	if not ok2 or type(data) ~= "table" then
		return nil
	end
	local results = {}
	for _, r in ipairs((data.web and data.web.results) or {}) do
		results[#results + 1] = { title = r.title, url = r.url, description = r.description }
	end
	return results
end

-- Run a Tavily search. Last resort: throws on any failure.
local function search_tavily(query, max, key)
	local res = yuke.http.post("https://api.tavily.com/search", {
		headers = { ["Content-Type"] = "application/json" },
		json = { api_key = key, query = query, max_results = max, search_depth = "basic" },
		timeout_ms = 15000,
	})
	if res == nil or res.status ~= 200 then
		local status = (res and res.status) or "?"
		local body = (res and res.body) or ""
		error(string.format("Tavily API error (%s): %s", status, body))
	end
	local data = yuke.json.decode(res.body)
	local results = {}
	for _, r in ipairs(data.results or {}) do
		results[#results + 1] = { title = r.title, url = r.url, description = r.content }
	end
	return results
end

-- Format results for the model: a header line per provider plus numbered entries.
local function format_results(query, results, provider, requested_max)
	local lines = {
		string.format('Query: "%s"', query),
		string.format("Provider: %s", provider),
		string.format("Results: %d (requested %d)", #results, requested_max),
		"",
	}
	if #results == 0 then
		lines[#lines + 1] = "No results found."
	else
		for i, r in ipairs(results) do
			lines[#lines + 1] = string.format("[%d] %s\nURL: %s\n%s", i, r.title, r.url, r.description)
			lines[#lines + 1] = ""
		end
	end
	return table.concat(lines, "\n")
end

yuke.tool({
	name = "web_search",
	description = "Search the web for information beyond the knowledge cutoff: recent events, library/API versions, or facts that may have changed. Returns results with title, URL, and a snippet. Account for Today's date in <env> — use the current year, not an older one, in queries for recent docs. `max_results` defaults to 5 (max 10).",
	params = { query = "string", max_results = "integer?" },
	handler = function(args)
		local query = args.query
		local max = args.max_results or 5
		max = math.max(1, math.min(10, max))
		local keys = load_keys()

		local results = nil
		local provider = "tavily"

		if keys.brave then
			results = search_brave(query, max, keys.brave)
			if results then
				provider = "brave"
			end
		end

		if not results then
			if not keys.tavily then
				error("Brave Search failed (or is not configured) and no TAVILY_API_KEY is set in ~/.yuke/.env. Both search providers are unavailable.")
			end
			results = search_tavily(query, max, keys.tavily)
			provider = "tavily"
		end

		return format_results(query, results, provider, max)
	end,
})

return true
