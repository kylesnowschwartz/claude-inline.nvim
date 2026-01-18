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

## Conversation History

Claude-Code by default stores conversation history, scoped per working directory, in ~/.claude/projects

These JSONL files contain critical insight into how Claude-Code operates. But they are also private, and not backed up. You can READ ONLY from these files, but never use private personal data from within them in documentation, and never remove or clear them.

These files are huge. Parse their keys with jq before trying to read the contents of said keys.

## Critical Implementation Details

These are hard-won lessons. Each represents a debugging session that uncovered non-obvious behavior.

### Environment Inheritance
**Principle:** Never filter environment variables when spawning Claude CLI. It needs HOME, auth tokens, and other variables to function. Let the process inherit the full environment.

### Spinner Race Condition
**Principle:** Timers and async callbacks create race conditions. The loading spinner's timer can overwrite real content if not stopped first. Always cancel async operations before processing their replacement.

### Buffer Line Indexing
**Principle:** Lua arrays are 1-indexed, Neovim APIs are 0-indexed. This off-by-one difference can be exploited intentionally but causes bugs if forgotten. Be explicit about which indexing system each variable uses.

### Extmark Drift
**Principle:** `nvim_buf_set_lines` on a single line is delete+insert, not update. Extmarks with right_gravity drift forward on each "update". Use `nvim_buf_set_text` for true in-place modifications that don't affect extmark positions.

**Corollary:** Keep right_gravity=true (default) for extmarks that should move when content is inserted before them.

### Parallel Task Nesting
**Principle:** Don't infer parent-child relationships from call order when operations can run in parallel. Claude CLI provides explicit `parent_tool_use_id` on messages - use it instead of maintaining a stack.

### Streaming Text Rendering
**Core insight:** Streaming text works by **replacing an entire region** with accumulated content on each update, not by appending chunks. Appending individual chunks creates word-per-line output because each append becomes a new line.

**The interleaving problem:** Claude responses can interleave text and tools: `text -> tool -> text -> tool -> final_text`. Once tools occupy buffer space, you can't replace "from header to end" without wiping them.

**Solution pattern:** Track separate regions with extmarks. Each region (pre-tool text, tools, post-tool text) gets its own tracked position. Update each region by replacing it entirely with accumulated content for that region.

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

**Lifecycle:** Tool display follows the Claude CLI stream-json event sequence: block starts (show placeholder) -> input streams in (update display) -> block stops -> result arrives (finalize with status). Tools are tracked with extmarks for position stability.

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
