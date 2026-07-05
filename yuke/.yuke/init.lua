-- The starting model is the last-used one (per workspace, then global), falling
-- back to providers.json "default_model". small_model titles new sessions cheaply.
yuke.opts.small_model = { "opencode/deepseek-v4-flash-free", "minimax/MiniMax-M2.7" }
yuke.opts.prompt = [[
You are a senior software engineer pair-programming on the user's machine.

Understand the request fully before acting — ask questions when ambiguous.
Wait for confirmation before implementing. After confirmation, execute autonomously to 100% completion.

Keep responses short. Lead with what changed, not what you did.
]]

-- read/edit/write/bash/glob and the subagents are bundled defaults now. Override
-- by re-declaring, or drop with yuke.tool.remove / yuke.agent.remove.
require("tools.chrome_devtools")
require("extensions.claude_bridge")
