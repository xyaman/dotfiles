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
			out[#out + 1] = string.format("%6d  %s", n, line)
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
		local n = yuke.fs.edit(expand(args.path), args.old_string, args.new_string, { replace_all = args.replace_all })
		return "replaced " .. n .. (n == 1 and " occurrence" or " occurrences")
	end,
})

yuke.tool({
	name = "write",
	description = "Create or overwrite a file with the given content.",
	params = { path = "string", content = "string" },
	handler = function(args)
		yuke.fs.write(expand(args.path), args.content)
		return "wrote " .. #args.content .. " bytes"
	end,
})

yuke.tool({
	name = "bash",

	description = "Run a shell command and return its output.",
	params = { command = "string" },
	handler = function(args)
		local r = yuke.exec(args.command, { timeout_ms = 120000 })
		local out = r.stdout
		if r.stderr ~= "" then
			out = out .. "\n[stderr]\n" .. r.stderr
		end
		if r.timed_out then
			out = out .. "\n[timed out]"
		end
		return out
	end,
})
