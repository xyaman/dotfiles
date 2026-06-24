-- Chrome DevTools tools for yuke: list/navigate/eval/screenshot a Chromium
-- browser over CDP, auto-launching a headless one when none is running.
-- Ported from pi-chrome-devtools:
-- https://github.com/narumiruna/pi-extensions/tree/main/extensions/pi-chrome-devtools
--
-- Env: YUKE_CHROME_HOST, YUKE_CHROME_PORT (set => attach-only, no auto-launch),
--      YUKE_CHROME_BROWSER (explicit executable), YUKE_CHROME_HEADLESS=0 (window).

local configured_port = tonumber(yuke.env.get("YUKE_CHROME_PORT") or "")
local headless = yuke.env.get("YUKE_CHROME_HEADLESS") ~= "0"

-- Session-scoped state, persisting across tool calls (module locals live for the session).
local state = {
	host = yuke.env.get("YUKE_CHROME_HOST") or "127.0.0.1",
	port = configured_port, -- nil => discover via auto-launched dynamic port
	port_configured = configured_port ~= nil,
	browser_pid = nil,
	user_data_dir = nil,
	active_page = nil,
}

-- Single-quote a string for a `sh -c` argument.
local function shquote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Drop trailing whitespace (command output carries a newline).
local function trim(s)
	return (tostring(s or ""):gsub("%s+$", ""))
end

-- DevTools `/json` base URL.
local function endpoint()
	return string.format("http://%s:%d", state.host, state.port or 0)
end

-- Does `/json/version` answer on the current endpoint?
local function endpoint_alive()
	if not state.port then
		return false
	end
	local ok, r = pcall(yuke.http.get, endpoint() .. "/json/version", { timeout_ms = 1000 })
	return ok and r ~= nil and r.status == 200
end

-- OS family: "windows", "macos", or "linux".
local function os_family()
	if yuke.env.get("OS") == "Windows_NT" then
		return "windows"
	end
	if trim(yuke.exec("uname -s").stdout) == "Darwin" then
		return "macos"
	end
	return "linux"
end

-- Browser executables to try, per platform. Launch/cleanup is POSIX, so native
-- Windows needs a POSIX shell (WSL, Git Bash) on PATH.
local function browser_candidates()
	local fam = os_family()
	if fam == "macos" then
		return {
			"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
			"/Applications/Chromium.app/Contents/MacOS/Chromium",
			"/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
			"/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
			"google-chrome",
			"chromium",
			"brave",
			"microsoft-edge",
		}
	end
	if fam == "windows" then
		local list = {}
		local roots = { yuke.env.get("PROGRAMFILES"), yuke.env.get("PROGRAMFILES(X86)"), yuke.env.get("LOCALAPPDATA") }
		for i = 1, 3 do
			local root = roots[i]
			if root and root ~= "" then
				list[#list + 1] = root .. "\\Google\\Chrome\\Application\\chrome.exe"
				list[#list + 1] = root .. "\\Chromium\\Application\\chrome.exe"
				list[#list + 1] = root .. "\\BraveSoftware\\Brave-Browser\\Application\\brave.exe"
				list[#list + 1] = root .. "\\Microsoft\\Edge\\Application\\msedge.exe"
			end
		end
		for _, n in ipairs({ "chrome.exe", "chromium.exe", "brave.exe", "msedge.exe" }) do
			list[#list + 1] = n
		end
		return list
	end
	return {
		"google-chrome",
		"google-chrome-stable",
		"chromium",
		"chromium-browser",
		"brave-browser",
		"brave",
		"microsoft-edge",
		"microsoft-edge-stable",
	}
end

-- First browser found, or nil; an explicit override wins.
local function browser_executable()
	local override = yuke.env.get("YUKE_CHROME_BROWSER")
	if override and override ~= "" then
		return override
	end
	for _, name in ipairs(browser_candidates()) do
		local r = yuke.exec("command -v " .. shquote(name))
		if r.code == 0 and trim(r.stdout) ~= "" then
			return trim(r.stdout)
		end
	end
	return nil
end

-- Poll Chrome's DevToolsActivePort file for the chosen dynamic port.
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

-- Launch a browser on a dynamic port with a temp profile; record pid, dir, port.
local function launch_browser()
	local exe = browser_executable()
	if not exe then
		error("no Chromium-family browser found on PATH; set YUKE_CHROME_BROWSER to an executable")
	end
	local dir = trim(yuke.exec({ "mktemp", "-d", "-t", "yuke-chrome-XXXXXX" }).stdout)
	if dir == "" then
		error("could not create a temp profile directory")
	end
	local flags = "--remote-debugging-port=0 --no-first-run --no-default-browser-check --user-data-dir="
		.. shquote(dir)
		.. (headless and " --headless=new" or "")
	-- Backgrounded and reparented so it survives the launching shell; `$!` is its pid.
	local cmd = shquote(exe) .. " " .. flags .. " about:blank >/dev/null 2>&1 </dev/null & echo $!"
	local r = yuke.exec(cmd, { timeout_ms = 15000 })
	state.browser_pid = tonumber((r.stdout or ""):match("%d+"))
	state.user_data_dir = dir
	state.port = read_active_port(dir, 10000)
end

-- Kill the managed browser and remove its profile; shared by chrome_quit and vm_stop.
local function shutdown_browser()
	if not state.browser_pid then
		return "no managed browser to shut down"
	end
	local pid = state.browser_pid
	yuke.exec("kill " .. pid .. " 2>/dev/null")
	-- Wait for exit before rm, else Chrome recreates files mid-delete.
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
end

-- Ensure a live endpoint, auto-launching if allowed.
local function ensure_endpoint()
	if endpoint_alive() then
		return
	end
	if state.port_configured then
		error(string.format("no Chrome DevTools endpoint at %s (YUKE_CHROME_PORT set, so auto-launch is off)", endpoint()))
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

-- One CDP connection: `send(method, params)` does a request/response round trip,
-- skipping event frames. Mirrors pi's withCdp/client.send.
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

-- Percent-encode for a URL query (RFC 3986 unreserved set).
local function urlencode(s)
	return (s:gsub("[^%w%-_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- Create a page via `PUT /json/new`.
local function create_page(url)
	ensure_endpoint()
	local r = yuke.http.put(endpoint() .. "/json/new?" .. urlencode(url or "about:blank"), { timeout_ms = 2000 })
	if r.status ~= 200 then
		error("Chrome DevTools /json/new returned " .. tostring(r.status) .. ": " .. (r.body or ""))
	end
	local page = yuke.json.decode(r.body)
	if page.type ~= "page" or not page.webSocketDebuggerUrl then
		error("Chrome DevTools created a target that is not an inspectable page")
	end
	return page
end

-- Resolve a page: explicit id, else active, else first, else nil.
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
		return string.format("%s %s to %s", created and "Created page and navigated" or "Navigated", page.id, args.url)
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
		-- Return the PNG inline so a vision model sees it.
		return {
			text = string.format("Screenshot of %s (saved to %s)", page.id, path),
			image = { base64 = data, mime = "image/png" },
		}
	end,
})

yuke.tool({
	name = "chrome_quit",
	description = "Shut down the headless Chrome browser these tools auto-launched and remove its temp profile.",
	params = {},
	handler = function()
		return shutdown_browser()
	end,
})

-- Kill the browser on VM shutdown so it does not linger (pi's session_shutdown cleanup).
yuke.on("vm_stop", function()
	shutdown_browser()
end)

return true
