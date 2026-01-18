# claude-inline.nvim

Minimal Claude chat for Neovim. Send prompts to Claude Code CLI with persistent conversation context in a sidebar.

## Features

- **Persistent Conversation**: Claude remembers context across messages (same process)
- **Sidebar Chat**: Conversation history in a dedicated split window
- **Floating Input**: Clean prompt input without leaving your code
- **Streaming Responses**: See Claude's response as it's generated
- **Tool Use Display**: See when Claude reads files, runs commands (single-line format)
- **Collapsible Messages**: User/assistant messages fold for clean navigation
- **Zero Dependencies**: Pure Neovim Lua, no external plugins required

## Installation

### lazy.nvim

```lua
{
  "kylesnowschwartz/claude-inline.nvim",
  config = function()
    require("claude-inline").setup()
  end,
}
```

### Manual

Clone to your Neovim packages directory:

```bash
git clone https://github.com/kylesnowschwartz/claude-inline.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/claude-inline.nvim
```

## Configuration

```lua
require("claude-inline").setup({
  keymaps = {
    send = '<leader>cs',      -- Send prompt
    toggle = '<leader>ct',    -- Toggle sidebar
    clear = '<leader>cx',     -- Clear conversation
  },
  ui = {
    sidebar = {
      position = 'right',     -- 'left' or 'right'
      width = 0.4,            -- 40% of editor width
    },
    input = {
      border = 'rounded',
      width = 60,
      height = 3,
    },
  },
})
```

## Usage

1. Press `<leader>cs` (or `:ClaudeInlineSend`) to open the prompt input
2. Type your question and press `Enter`
3. Response appears in the sidebar with streaming
4. Send follow-up questions - Claude remembers context
5. Press `<leader>cx` (or `:ClaudeInlineClear`) to start a new conversation

### Visual Selection

Select code in visual mode, then press `<leader>cs`. The floating input opens for your prompt, and the selected code is automatically included with file path and line numbers:

```
From main.lua:15-23:
local function example()
  -- your selected code
end

What does this function do?
```

This gives Claude the context it needs without you having to copy-paste or explain where the code lives.

## Commands

| Command | Description |
|---------|-------------|
| `:ClaudeInlineSend` | Open input prompt |
| `:ClaudeInlineToggle` | Toggle sidebar visibility |
| `:ClaudeInlineClear` | Clear conversation and restart |

## How It Works

The plugin spawns a single Claude Code CLI process with `--input-format stream-json --output-format stream-json`. This keeps the conversation context in memory, so follow-up questions work naturally without re-sending history.

Messages are sent as NDJSON:
```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"your prompt"}]}}
```

Claude responds with streaming chunks (`type: "assistant"`) followed by a final result (`type: "result"`).

When Claude uses tools (reading files, running bash commands), the plugin displays single-line entries:
```
Read(init.lua) ✓ 45ms
Bash(npm test) ✗ exit 1
```

For Task agents (sub-agents), children are grouped under the parent with indentation.

## License

MIT
