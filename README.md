# claude-inline.nvim

Cursor-style inline AI editing for Neovim, powered by Claude Code CLI.

Select code in visual mode, open the Claude terminal, describe a change, and get a native Neovim diff you can accept or reject.

## Features

- **Claude Code Integration**: Communicates with Claude Code CLI via WebSocket
- **Selection Tracking**: Visual selections are automatically shared with Claude
- **Native Diff View**: Changes appear in a standard Neovim diff
- **Simple Accept/Reject**: `:w` to accept changes, close buffer to reject

## Requirements

- Neovim 0.8+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated

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

### packer.nvim

```lua
use({
  "kylesnowschwartz/claude-inline.nvim",
  config = function()
    require("claude-inline").setup()
  end,
})
```

## Configuration

```lua
require("claude-inline").setup({
  mappings = {
    toggle_terminal = "<leader>cc",  -- Toggle Claude terminal sidebar
  },
})
```

No API keys required - Claude Code CLI handles authentication.

## Usage

1. **Select code** in visual mode
2. **Exit visual mode** (press `Esc`) - selection is captured
3. **Open Claude terminal** with `<leader>cc`
4. **Ask Claude** to modify your selection (e.g., "add error handling to @selection")
5. **Review the diff** that appears
6. **Accept** with `:w` or **reject** by closing the buffer

## How It Works

The plugin creates a WebSocket server that Claude Code CLI connects to. When you:

- **Select code**: The selection is tracked and can be referenced as `@selection` in Claude
- **Ask for changes**: Claude calls the `openDiff` tool to show proposed changes
- **Accept/Reject**: Your decision is sent back to Claude Code

### Lock File

The plugin creates a lock file at `~/.claude/ide/<port>.lock` so Claude Code CLI can discover and connect to it automatically.

## Commands

| Command | Description |
|---------|-------------|
| `:lua require("claude-inline").toggle_terminal()` | Toggle Claude terminal |
| `:lua require("claude-inline").start()` | Start WebSocket server |
| `:lua require("claude-inline").stop()` | Stop WebSocket server |
| `:lua require("claude-inline").get_status()` | Get server status |

## Troubleshooting

### Claude Code not connecting

1. Check the lock file exists: `ls ~/.claude/ide/`
2. Verify server is running: `:lua print(require("claude-inline").is_running())`
3. Check the port: `:lua print(require("claude-inline").get_status().port)`

### Selection not appearing in Claude

1. Make sure you exit visual mode after selecting (press `Esc`)
2. The selection is stored when you exit visual mode, not while selecting

## License

MIT
