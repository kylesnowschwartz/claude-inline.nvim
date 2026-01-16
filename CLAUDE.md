# claude-inline.nvim

Minimal Neovim plugin for chatting with Claude CLI. Persistent conversation context via stream-json format.

## Architecture

```
User types prompt -> Floating input window -> Send to Claude process -> Parse NDJSON response -> Display in sidebar
```

Single Claude CLI process stays alive, maintaining conversation memory. No WebSocket, no MCP, no complexity.

## Key Files

```
lua/claude-inline/
├── init.lua      # Entry point, commands, keymaps, message routing
├── client.lua    # Claude process lifecycle, NDJSON parsing
├── ui.lua        # Sidebar split, floating input, loading spinner
├── selection.lua # Visual mode capture with proper mode handling
└── config.lua    # Defaults and user config merge
```

**Total: ~500 lines of Lua, zero external dependencies.**

## How It Works

### Claude CLI Invocation
```bash
claude -p --input-format stream-json --output-format stream-json
```

The `-p` flag runs in print mode (non-interactive). Stream-json keeps conversation context in the running process.

### Message Format (Input)
```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"your prompt"}]}}
```

### Message Types (Output)
- `type: "system"` - Hook responses, init info. **Ignore these.**
- `type: "assistant"` - Response content in `msg.message.content[].text`
- `type: "result"` - Final result in `msg.result`, signals completion

### Flow
1. `init.lua:send()` - Shows sidebar, appends user message, starts client if needed
2. `client.lua:start()` - Spawns Claude process with `vim.uv.spawn()`, sets up NDJSON reader
3. `client.lua:send()` - Writes JSON line to stdin
4. NDJSON lines arrive on stdout, parsed and dispatched to `handle_message()`
5. `handle_message()` stops spinner on first content, updates sidebar text
6. On `result` message, streaming state resets for next turn

## Critical Implementation Details

### Environment Inheritance
Claude CLI needs full environment for auth credentials. **Do not filter:**
```lua
-- WRONG: strips HOME, auth tokens, etc.
local env = { 'PATH=' .. vim.fn.getenv('PATH') }
uv.spawn(cmd, { args = args, env = env, ... })

-- RIGHT: inherit everything
uv.spawn(cmd, { args = args, stdio = {...} }, callback)
```

### Spinner Race Condition
The loading spinner runs on a 100ms timer calling `update_last_message()`. When Claude responds, we also call `update_last_message()` with actual content. **Must stop spinner BEFORE processing assistant message**, or timer overwrites response:
```lua
if msg_type == 'assistant' then
  ui.hide_loading()  -- FIRST: stop the timer
  -- THEN: process content
end
```

### Buffer Line Indexing
Lua arrays are 1-indexed, `nvim_buf_set_lines` is 0-indexed. The code exploits this: when we find `**Claude:**` at Lua index `i`, passing `i` to `nvim_buf_set_lines` replaces content AFTER that line (which is what we want).

## Commands & Keymaps

| Command | Default Key | Mode | Action |
|---------|-------------|------|--------|
| `:ClaudeInlineSend` | `<leader>cs` | Normal | Open floating input prompt |
| `:ClaudeInlineSend` | `<leader>cs` | Visual | Send selection with prompt (includes filepath:lines context) |
| `:ClaudeInlineToggle` | `<leader>ct` | Normal | Toggle sidebar visibility |
| `:ClaudeInlineClear` | `<leader>cx` | Normal | Clear conversation, restart Claude process |

## Configuration

```lua
require('claude-inline').setup({
  keymaps = {
    send = '<leader>cs',
    toggle = '<leader>ct',
    clear = '<leader>cx',
  },
  ui = {
    sidebar = { position = 'right', width = 0.4 },
    input = { border = 'rounded', width = 60, height = 3 },
  },
})
```

## Testing (Manual)

No automated tests yet. Manual verification:
1. `:lua require('claude-inline').setup()`
2. `<leader>cs` -> type "Hello" -> Enter
3. Verify response appears in sidebar
4. Send follow-up "What did I just say?" -> verify context retained
5. `<leader>cx` -> verify fresh conversation starts

## Future Ideas

- Syntax highlighting in sidebar (treesitter markdown)
- Keybind to yank Claude's last response
- Conversation history persistence across sessions

## Reference Implementations

**Before implementing new features, check `.cloned-sources/` for existing patterns.**

```
.cloned-sources/
├── avante.nvim/       # Popular AI chat plugin
├── claude-inline.nvim/ # Reference inline editing implementation
└── claudecode.nvim/   # Official Claude Code Neovim integration
```

These repos contain battle-tested solutions for common problems:
- **Visual selection handling**: See `selection.lua` in both claude-inline.nvim and claudecode.nvim
- **Terminal integration**: claudecode.nvim has comprehensive terminal management
- **WebSocket/MCP protocol**: claudecode.nvim implements full MCP compliance

**Research pattern:**
1. Identify the feature area (e.g., "visual selection")
2. `rg "visual.*selection|getpos" .cloned-sources/` to find relevant files
3. Read the implementations, understand the patterns
4. Adapt to this plugin's simpler architecture

Don't reinvent solutions that already exist in the reference implementations.

## Development Commands

```bash
# Syntax check
luajit -bl lua/claude-inline/*.lua > /dev/null && echo "OK"

# Test Claude CLI format directly
echo '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hi"}]}}' | claude -p --input-format stream-json --output-format stream-json

# Load in Neovim for testing
nvim --cmd "set rtp+=~/Code/my-projects/claude-inline.nvim"
```
