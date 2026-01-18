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
├── init.lua        # Entry point, commands, keymaps, message routing
├── client.lua      # Claude process lifecycle, NDJSON parsing
├── config.lua      # Defaults and user config merge
├── debug.lua       # Debug logging to /tmp/claude-inline-debug.log
├── health.lua      # :checkhealth support
├── selection.lua   # Visual mode capture with proper mode handling
└── ui/
    ├── init.lua    # UI facade, re-exports all components
    ├── state.lua   # Shared state (windows, buffers, blocks)
    ├── sidebar.lua # Sidebar window management
    ├── input.lua   # Floating input window
    ├── loading.lua # Spinner animation
    ├── buffer.lua  # Buffer utilities (modifiable, extmarks)
    ├── fold.lua    # Foldexpr/foldtext for collapsible sections
    └── blocks/
        ├── init.lua      # Block registry, clear_all
        ├── message.lua   # User/assistant message blocks
        ├── tool_use.lua  # Tool invocation display
        ├── tool_result.lua # Tool result display
        └── format.lua    # Tool formatting helpers
```

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
- `type: "stream_event"` - Granular streaming events (with `--include-partial-messages`):
  - `event.type: "content_block_start"` with `content_block.type`:
    - `"text"` - Text response
    - `"tool_use"` - Tool invocation (includes `name`, `id`)
  - `event.type: "content_block_delta"` with `delta.type`:
    - `"text_delta"` - Incremental text content
    - `"input_json_delta"` - Streaming JSON for tool input parameters
  - `event.type: "content_block_stop"` - Block finished streaming
- `type: "assistant"` - Response content in `msg.message.content[]`:
  - `type: "text"` - Text content in `.text`
  - `type: "tool_use"` - Tool call with `.name`, `.id`, `.input`
- `type: "user"` - Tool results returned to Claude:
  - `type: "tool_result"` - Result with `.tool_use_id`, `.content`, `.is_error`
  - `tool_use_result` - Metadata: `durationMs`, `numFiles`, `exitCode`, `truncated`
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

### Extmark Drift with nvim_buf_set_lines
**Problem:** `nvim_buf_set_lines(buf, line, line+1, ...)` looks like an "update" but is actually delete+insert. With `right_gravity=true` (default), extmarks at that position drift forward on every "update".

**Symptom:** Extmarks tracking tool positions slowly drift to wrong lines after input streaming updates.

**Solution:** Use `nvim_buf_set_text` for in-place line content updates - it modifies text without delete+insert semantics:
```lua
-- WRONG: extmarks drift forward
vim.api.nvim_buf_set_lines(buf, line_num, line_num + 1, false, { new_text })

-- RIGHT: extmarks stay put
local old_line = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1] or ''
vim.api.nvim_buf_set_text(buf, line_num, 0, line_num, #old_line, { new_text })
```

Keep `right_gravity=true` (default) so extmarks move when lines are inserted BEFORE them - that behavior is correct for tracking dynamic positions.

### Parallel Task Nesting with parent_tool_use_id
**Problem:** When Claude runs parallel Task agents, their children interleave. A stack-based model incorrectly nests Task 2 inside Task 1.

**Solution:** Claude CLI provides `parent_tool_use_id` on messages:
- Top-level tools: `parent_tool_use_id: null`
- Sub-agent tools: `parent_tool_use_id: "<task_id_that_spawned_this>"`

Use this explicit parent ID instead of inferring from a stack:
```lua
-- In stream_event handler:
local parent_id = msg.parent_tool_use_id  -- nil for top-level, task_id for children
ui.show_tool_use(block.id, block.name, block.input, parent_id)
```

### Tool Use Display
When Claude invokes tools (read files, run commands, etc.), the plugin displays single-line entries:

**Regular tool:**
```
Read(init.lua) ...          # While running
Read(init.lua) ✓ 45ms       # Success with duration
Bash(npm test) ✗ exit 1     # Error with exit code
```

**Task (sub-agent) with children:**
```
[Task abc123: Find most starred repo]
  Bash(gh search repos --sort stars) ✓
  Read(results.json) ✓
[Task abc123] ✓ 12.5s, 2 tools
  The most starred repo is freeCodeCamp.
```

When `tool_use_result` metadata is available, results show file counts, duration, exit codes, and truncation status.

Flow:
1. `content_block_start` with `type: "tool_use"` triggers `ui.show_tool_use()`
2. `content_block_delta` with `type: "input_json_delta"` streams parameters via `ui.update_tool_input()`
3. `content_block_stop` finalizes with `ui.complete_tool()`
4. `user` message with `type: "tool_result"` triggers `ui.show_tool_result()` - updates line in-place
5. Claude continues with response text

Tools are tracked with extmarks so parallel Task children are correctly positioned under their parent.

## Commands & Keymaps

| Command | Default Key | Mode | Action |
|---------|-------------|------|--------|
| `:ClaudeInlineSend` | `<leader>cs` | Normal | Open floating input prompt |
| `:ClaudeInlineSend` | `<leader>cs` | Visual | Send selection with prompt (includes filepath:lines context) |
| `:ClaudeInlineToggle` | `<leader>ct` | Normal | Toggle sidebar visibility |
| `:ClaudeInlineClear` | `<leader>cx` | Normal | Clear conversation, restart Claude process |
| `:ClaudeInlineDebug on\|off` | - | Normal | Toggle debug logging |
| `:checkhealth claude-inline` | - | Normal | Verify Claude CLI and dependencies |

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
  debug = false,  -- Enable to log messages to /tmp/claude-inline-debug.log
})
```

## Debugging

Enable debug logging to inspect message flow:

```lua
-- In setup
require('claude-inline').setup({ debug = true })

-- Or at runtime
:ClaudeInlineDebug on
:ClaudeInlineDebug off
```

Log file: `/tmp/claude-inline-debug.log`

Shows message types, stream events, and content block metadata. Useful for diagnosing issues with response parsing or duplicate content.

## Testing

Automated tests in `tests/`:
- `ui_spec.lua` - UI component tests (messages, folds, tool display)
- `streaming_integration_spec.lua` - End-to-end message handling

```bash
# Run all tests
just test

# Run specific test file
nvim --headless -u tests/minimal_init.lua -c "lua require('tests.ui_spec').run()"

# Run streaming tests
just test-streaming
```

Manual verification:
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
# Syntax check all files
just check

# Or manually:
find lua -name "*.lua" -exec luajit -bl {} \; > /dev/null && echo "OK"

# Run tests
just test

# Test Claude CLI format directly
echo '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hi"}]}}' | claude -p --input-format stream-json --output-format stream-json

# Load in Neovim for testing
nvim --cmd "set rtp+=."
```
