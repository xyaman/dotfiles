# claude_bridge

Yuke provider extension that bridges to Claude Code via the Agent SDK.

## Requirements

- Node.js >= 20
- Claude Code CLI installed and authenticated (`claude` on PATH, or override via `setup({ claude_path = "..." })`)
- `npm install` in this directory

## Install

```sh
cd ~/.yuke/extensions/claude_bridge
npm install
```

Then in `~/.yuke/init.lua`:

```lua
require("extensions.claude_bridge")
-- optional:
-- require("extensions.claude_bridge").setup({
--   system_prompt_mode = "preset",  -- "replace" (default) | "preset" | "none"
-- })
```

And add to `~/.yuke/providers.json`:

```json
{
  "name": "claude-bridge",
  "protocol": "lua",
  "models": [
    { "name": "opus-4.8",   "context_window": 1000000 },
    { "name": "sonnet-5",   "context_window": 1000000 },
    { "name": "haiku-4.5",  "context_window":  200000 }
  ]
}
```

## Reference

Modeled on [pi-claude-bridge](https://github.com/elidickinson/pi-claude-bridge).
Reference commit: `756c7e6` (v0.6.1); `systemPromptMode` from PR #21 (`593a181`).
