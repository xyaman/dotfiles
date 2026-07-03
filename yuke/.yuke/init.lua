yuke.opts.default_model = "minimax/MiniMax-M3"
yuke.opts.prompt = [[
You are a senior software engineer pair-programming on the user's machine.

Understand the request fully before acting — ask questions when ambiguous.
Wait for confirmation before implementing. After confirmation, execute autonomously to 100% completion.

Keep responses short. Lead with what changed, not what you did.
]]

-- Expand a leading "~" to $HOME so tools can take home-relative paths.
local home = yuke.env.get("HOME")
local function expand(path)
	if home and (path == "~" or path:sub(1, 2) == "~/") then
		return home .. path:sub(2)
	end
	return path
end

yuke.tool({
	name = "read",
	description = "Read a file with 1-indexed line numbers. Optionally pass start/end to read a range without loading the whole file.",
	params = { path = "string", start = "integer", ["end"] = "integer" },
	handler = function(args)
		local text = yuke.fs.read(expand(args.path), args.start, args["end"])
		local out, n = {}, args.start or 1
		for line in (text .. "\n"):gmatch("(.-)\n") do
			out[#out + 1] = string.format("%d: %s", n, line)
			n = n + 1
		end
		return table.concat(out, "\n")
	end,
})

yuke.tool({
	name = "edit",
	description = "Replace an exact string in a file. old_string must be unique unless replace_all is true.",
	params = { path = "string", old_string = "string", new_string = "string", replace_all = "boolean" },
	handler = function(args)
		local path = expand(args.path)
		local before = yuke.fs.read(path)
		local n = yuke.fs.edit(path, args.old_string, args.new_string, { replace_all = args.replace_all })
		local after = yuke.fs.read(path)
		local diff = yuke.diff(before, after, { path = args.path })
		return {
			text = "replaced " .. n .. (n == 1 and " occurrence" or " occurrences"),
			view = { kind = "diff", diff = diff },
		}
	end,
})

yuke.tool({
	name = "write",
	description = "Create or overwrite a file with the given content.",
	params = { path = "string", content = "string" },
	handler = function(args)
		local path = expand(args.path)
		local before = yuke.fs.exists(path) and yuke.fs.read(path) or ""
		yuke.fs.write(path, args.content)
		local diff = yuke.diff(before, args.content, { path = args.path })
		return {
			text = "wrote " .. #args.content .. " bytes",
			view = { kind = "diff", diff = diff },
		}
	end,
})

yuke.tool({
	name = "bash",
	description = "Run a shell command and return stdout, stderr, and exit code. Each call runs in a fresh shell at the workspace root; `cwd` is optional. Avoid `cd DIR && ...` when you expect the directory change to stick.\n\n`timeout_ms` is optional (default 120000, max 600000). Pass a larger value for long-running commands.",
	params = { command = "string", cwd = "string?", timeout_ms = "integer?" },
	handler = function(args)
		local timeout_ms = args.timeout_ms or 120000
		if timeout_ms > 600000 then
			timeout_ms = 600000
		end
		local r = yuke.exec(args.command, { cwd = args.cwd, timeout_ms = timeout_ms })
		local out = r.stdout
		if r.stderr ~= "" then
			out = out .. "\n[stderr]\n" .. r.stderr
		end
		if r.timed_out then
			out = out
				.. "\n\n[exit code: " .. r.code .. "]"
				.. "\n[timed out after " .. timeout_ms .. "ms — retry with a larger timeout_ms if the command needs more time]"
		else
			out = out .. "\n[exit code: " .. r.code .. "]"
		end
		return out
	end,
})

-- Load extra tool bundles that live beside this config. The daemon already adds
-- ~/.yuke to package.path (add_search_dir), so this resolves to
-- ~/.yuke/tools/chrome_devtools.lua.
require("tools.chrome_devtools")

-- Subagents: register agents with yuke.agent{...}, then spawn them via a Task tool.
-- Read-only agents get {read, bash} and are told not to edit; `general` omits
-- `tools` so it inherits the full set (minus Task) for write-capable delegation.
yuke.agent({
	name = "researcher",
	description = "Read-only investigator: explores the codebase and reports findings.",
	tools = { "read", "bash" },
	system = [[
You are a research subagent. Investigate what the caller asks using read and bash
(read-only). Report concise findings with file:line references. Do not modify files.
]],
})

yuke.agent({
	name = "planner",
	description = "Read-only architect: designs an implementation approach without editing.",
	tools = { "read", "bash" },
	system = [[
You are a planning subagent. Investigate with read and bash, then propose a concrete,
step-by-step implementation approach: the files to touch, the order, and the risks.
Do NOT edit any files. Return the plan, not a diff.
]],
})

yuke.agent({
	name = "reviewer",
	description = "Read-only code reviewer: critiques a diff or files for bugs and issues.",
	tools = { "read", "bash" },
	system = [[
You are a code-review subagent. Read the diff or files the caller names (use git via
bash for diffs) and report concrete correctness, security, and clarity issues with
file:line references, most severe first. Do NOT modify files.
]],
})

yuke.agent({
	name = "general",
	description = "General-purpose agent for multi-step tasks; can read, write, and run commands.",
	system = [[
You are a general-purpose subagent. Carry out the caller's task autonomously to
completion using the available tools, then report what you did and any follow-ups.
]],
})

-- Build the Task description + subagent_type enum from the agents registered
-- above, at init time (like codex/opencode: names live in the description, not a
-- static string). Re-runs on every session build, so it is always current.
local function build_task_spec()
	local lines, enum = {}, {}
	for _, name in ipairs(yuke.agent._order) do
		local a = yuke.agent._by_name[name]
		lines[#lines + 1] = "- " .. name .. ": " .. (a.description or "")
		enum[#enum + 1] = name
	end
	local description = "Delegate a subtask to a specialized subagent that runs its own agent "
		.. "loop to completion and returns a final result. Use for well-scoped, read-heavy, or "
		.. "parallelizable work.\n\nAvailable subagent_type values:\n"
		.. table.concat(lines, "\n")
	return description, enum
end

-- Runs a registered subagent to completion and returns its final answer.
local task_description, task_enum = build_task_spec()
yuke.tool({
	name = "Task",
	description = task_description,
	params_json = yuke.json.encode({
		type = "object",
		properties = {
			subagent_type = { type = "string", enum = task_enum, description = "Which registered subagent to run." },
			description = { type = "string", description = "A short (3-5 word) description of the task." },
			prompt = { type = "string", description = "The task for the subagent to perform." },
		},
		required = { "subagent_type", "prompt" },
	}),
	handler = function(args)
		local a = yuke.agent._by_name[args.subagent_type]
		if not a then
			return "Error: unknown subagent_type '" .. tostring(args.subagent_type) .. "'"
		end
		return yuke.agent.run({ model = a.model, system = a.system, tools = a.tools }, args.prompt)
	end,
})
