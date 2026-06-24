-- Chrome DevTools Protocol tools for yuke.
--
-- Ports the core of narumiruna/pi-extensions' pi-chrome-devtools: drive a
-- Chromium-family browser over CDP to list pages, navigate, evaluate JS, and
-- capture screenshots. Attaches to a running endpoint, or auto-launches a
-- headless browser with an isolated temp profile when none is found.
--
-- Endpoint discovery uses yuke.http on the `/json` endpoints; the CDP
-- request/response traffic rides yuke.ws; screenshots decode via yuke.base64.
--
-- Env overrides:
--   YUKE_CHROME_HOST     DevTools host (default 127.0.0.1)
--   YUKE_CHROME_PORT     DevTools port; when set, auto-launch is disabled (attach only)
--   YUKE_CHROME_BROWSER  explicit browser executable, skipping PATH discovery

-- The ws primitive is required; fail loudly (but non-fatally) on an old binary.
if not yuke.ws or not yuke.base64 then
	yuke.log("chrome_devtools: yuke.ws/yuke.base64 missing; rebuild yuke. Tools not registered.")
	return false
end

-- Chromium-family executables tried on PATH, in order, when no override is set.
local CANDIDATES = {
	"google-chrome",
	"google-chrome-stable",
	"chromium",
	"chromium-browser",
	"brave-browser",
	"brave",
	"microsoft-edge",
	"microsoft-edge-stable",
}

local configured_port = tonumber(yuke.env.get("YUKE_CHROME_PORT") or "")

-- Session-scoped state: the live endpoint, managed browser, and selected page
-- persist across tool calls (module locals live for the whole session, like the
-- read guard in init.lua).
local state = {
	host = yuke.env.get("YUKE_CHROME_HOST") or "127.0.0.1",
	port = configured_port, -- nil => discover via auto-launched dynamic port
	port_configured = configured_port ~= nil,
	browser_pid = nil,
	user_data_dir = nil,
	active_page = nil,
}

-- Single-quote a string for safe interpolation into a `sh -c` command.
local function shquote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Trim trailing whitespace (command output carries a newline).
local function trim(s)
	return (tostring(s or ""):gsub("%s+$", ""))
end

-- The HTTP base for the DevTools `/json` endpoints.
local function endpoint()
	return string.format("http://%s:%d", state.host, state.port or 0)
end

-- True when `/json/version` answers on the current endpoint.
local function endpoint_alive()
	if not state.port then
		return false
	end
	local ok, r = pcall(yuke.http.get, endpoint() .. "/json/version", { timeout_ms = 1000 })
	return ok and r ~= nil and r.status == 200
end

-- First Chromium-family executable found, or nil. An explicit override wins.
local function browser_executable()
	local override = yuke.env.get("YUKE_CHROME_BROWSER")
	if override and override ~= "" then
		return override
	end
	for _, name in ipairs(CANDIDATES) do
		local r = yuke.exec("command -v " .. name)
		if r.code == 0 and trim(r.stdout) ~= "" then
			return trim(r.stdout)
		end
	end
	return nil
end

-- Read the dynamic port Chrome writes to its DevToolsActivePort file, polling
-- until it appears or the timeout elapses.
local function read_active_port(dir, timeout_ms)
	local file = dir .. "/DevToolsActivePort"
	local waited = 0
	while waited < timeout_ms do
		if yuke.fs.exists(file) then
			local port = tonumber((yuke.fs.read(file) or ""):match("^%s*(%d+)"))
			if port then
				return port
			end
		end
		yuke.sleep(200)
		waited = waited + 200
	end
	error("timed out waiting for DevToolsActivePort in " .. dir)
end

-- Launch a headless browser on a dynamic port with an isolated temp profile,
-- backgrounded so it outlives the launching shell. Records pid, dir, and port.
local function launch_browser()
	local exe = browser_executable()
	if not exe then
		error("no Chromium-family browser found on PATH; set YUKE_CHROME_BROWSER to an executable")
	end
	local dir = trim(yuke.exec({ "mktemp", "-d", "-t", "yuke-chrome-XXXXXX" }).stdout)
	if dir == "" then
		error("could not create a temp profile directory")
	end
	-- Background with redirects so the child reparents and is not killed when
	-- the launching `sh` exits; `$!` is the browser's own pid.
	local cmd = string.format(
		"%s --headless=new --remote-debugging-port=0 --user-data-dir=%s "
			.. "--no-first-run --no-default-browser-check about:blank "
			.. ">/dev/null 2>&1 </dev/null & echo $!",
		shquote(exe),
		shquote(dir)
	)
	local r = yuke.exec(cmd, { timeout_ms = 15000 })
	state.browser_pid = tonumber((r.stdout or ""):match("%d+"))
	state.user_data_dir = dir
	state.port = read_active_port(dir, 10000)
end

-- Ensure a reachable DevTools endpoint, auto-launching a browser if allowed.
local function ensure_endpoint()
	if endpoint_alive() then
		return
	end
	if state.port_configured then
		error(
			string.format(
				"no Chrome DevTools endpoint at %s (YUKE_CHROME_PORT is set, so auto-launch is disabled)",
				endpoint()
			)
		)
	end
	launch_browser()
	local waited = 0
	while waited < 5000 and not endpoint_alive() do
		yuke.sleep(200)
		waited = waited + 200
	end
	if not endpoint_alive() then
		error("launched a browser but its DevTools endpoint did not come up at " .. endpoint())
	end
end

-- Inspectable pages (type "page" with a debugger URL) at the live endpoint.
local function list_pages()
	ensure_endpoint()
	local r = yuke.http.get(endpoint() .. "/json/list", { timeout_ms = 2000 })
	if r.status ~= 200 then
		error("Chrome DevTools /json/list returned " .. tostring(r.status))
	end
	local pages = {}
	for _, p in ipairs(yuke.json.decode(r.body)) do
		if p.type == "page" and p.webSocketDebuggerUrl then
			pages[#pages + 1] = p
		end
	end
	return pages
end

-- Run `fn(send)` over a single CDP connection. `send(method, params)` does one
-- request/response round trip, skipping interleaved event frames. Mirrors pi's
-- withCdp/client.send. The socket is always closed.
local function with_cdp(ws_url, fn)
	local ws = yuke.ws.connect(ws_url, { timeout_ms = 10000 })
	local next_id = 0
	local function send(method, params)
		next_id = next_id + 1
		local id = next_id
		local msg = { id = id, method = method }
		if params then
			msg.params = params
		end
		ws:send(yuke.json.encode(msg))
		while true do
			local raw = ws:recv({ timeout_ms = 10000 })
			if raw == nil then
				error("timed out waiting for CDP response: " .. method)
			end
			local resp = yuke.json.decode(raw)
			if resp.id == id then
				if resp.error then
					error(string.format("CDP error %s: %s", tostring(resp.error.code), resp.error.message or ""))
				end
				return resp.result
			end
		end
	end
	local ok, result = pcall(fn, send)
	ws:close()
	if not ok then
		error(result, 0)
	end
	return result
end

-- The browser-level debugger URL, used to create new targets/pages.
local function browser_ws()
	local r = yuke.http.get(endpoint() .. "/json/version", { timeout_ms = 2000 })
	return yuke.json.decode(r.body).webSocketDebuggerUrl
end

-- Create a fresh page at `url` and return its page record.
local function create_page(url)
	ensure_endpoint()
	local target_id = with_cdp(browser_ws(), function(send)
		return send("Target.createTarget", { url = url or "about:blank" }).targetId
	end)
	for _, p in ipairs(list_pages()) do
		if p.id == target_id then
			return p
		end
	end
	error("created a target but could not find its inspectable page")
end

-- Resolve a page: an explicit id, else the active page, else the first page,
-- else nil (caller decides whether to create one).
local function resolve_page(page_id)
	local pages = list_pages()
	if page_id then
		for _, p in ipairs(pages) do
			if p.id == page_id then
				return p
			end
		end
		error("Chrome page not found: " .. page_id)
	end
	if state.active_page then
		for _, p in ipairs(pages) do
			if p.id == state.active_page then
				return p
			end
		end
	end
	return pages[1]
end

yuke.tool({
	name = "chrome_list_pages",
	description = "List inspectable Chrome tabs/pages (id, title, url) over Chrome DevTools Protocol. Auto-launches a headless browser if none is running.",
	params = {},
	handler = function()
		local out = {}
		for _, p in ipairs(list_pages()) do
			out[#out + 1] = string.format("%s  %s  %s", p.id, (p.title ~= "" and p.title or "(untitled)"), p.url)
		end
		if #out == 0 then
			return "No inspectable Chrome pages. Use chrome_navigate to create one."
		end
		return table.concat(out, "\n")
	end,
})

yuke.tool({
	name = "chrome_navigate",
	description = "Navigate a Chrome page to a URL over CDP, creating a page if none exists. Pass page_id to target a tab; otherwise the active/first page is used and becomes active.",
	params = { url = "string", page_id = "string?" },
	handler = function(args)
		local page = resolve_page(args.page_id)
		local created = false
		if not page then
			page = create_page("about:blank")
			created = true
		end
		with_cdp(page.webSocketDebuggerUrl, function(send)
			send("Page.navigate", { url = args.url })
		end)
		state.active_page = page.id
		return string.format(
			"%s %s to %s",
			created and "Created page and navigated" or "Navigated",
			page.id,
			args.url
		)
	end,
})

yuke.tool({
	name = "chrome_eval",
	description = "Evaluate a JavaScript expression in a Chrome page over CDP and return the result. Pass page_id to target a tab; await_promise defaults to true.",
	params = { expression = "string", page_id = "string?", await_promise = "boolean?" },
	handler = function(args)
		local page = resolve_page(args.page_id)
		if not page then
			error("no Chrome page available; run chrome_navigate first")
		end
		local result = with_cdp(page.webSocketDebuggerUrl, function(send)
			return send("Runtime.evaluate", {
				expression = args.expression,
				awaitPromise = args.await_promise ~= false,
				returnByValue = true,
			})
		end)
		state.active_page = page.id
		return yuke.json.encode(result)
	end,
})

yuke.tool({
	name = "chrome_screenshot",
	description = "Capture a PNG screenshot of a Chrome page over CDP and save it to a file, returning the path. full_page captures the whole document; save_path overrides the default temp file.",
	params = { page_id = "string?", full_page = "boolean?", save_path = "string?" },
	handler = function(args)
		local page = resolve_page(args.page_id)
		if not page then
			error("no Chrome page available; run chrome_navigate first")
		end
		local data = with_cdp(page.webSocketDebuggerUrl, function(send)
			if args.full_page then
				local cs = send("Page.getLayoutMetrics").contentSize
				return send("Page.captureScreenshot", {
					format = "png",
					captureBeyondViewport = true,
					clip = { x = cs.x, y = cs.y, width = cs.width, height = cs.height, scale = 1 },
				}).data
			end
			return send("Page.captureScreenshot", { format = "png" }).data
		end)
		state.active_page = page.id
		local path = args.save_path
		if not path or path == "" then
			path = trim(yuke.exec("mktemp -p /tmp --suffix=.png yuke-screenshot-XXXXXX").stdout)
		end
		yuke.fs.write(path, yuke.base64.decode(data))
		return string.format("Saved PNG screenshot of %s to %s", page.id, path)
	end,
})

yuke.tool({
	name = "chrome_quit",
	description = "Shut down the headless Chrome browser these tools auto-launched and remove its temp profile.",
	params = {},
	handler = function()
		if not state.browser_pid then
			return "no managed browser to shut down"
		end
		local pid = state.browser_pid
		yuke.exec("kill " .. pid .. " 2>/dev/null")
		-- Wait for the process to exit before removing its profile, else Chrome
		-- recreates files mid-delete and leaves the directory behind.
		local waited = 0
		while waited < 2000 and yuke.exec("kill -0 " .. pid .. " 2>/dev/null").code == 0 do
			yuke.sleep(100)
			waited = waited + 100
		end
		if state.user_data_dir then
			yuke.exec({ "rm", "-rf", state.user_data_dir })
		end
		state.browser_pid = nil
		state.user_data_dir = nil
		state.active_page = nil
		if not state.port_configured then
			state.port = nil
		end
		return "shut down managed browser (pid " .. pid .. ")"
	end,
})

return true
