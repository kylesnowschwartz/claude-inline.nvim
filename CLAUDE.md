# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Active Development Context

@.agent-history/context-packet-20260111.md

## Project Overview

claude-inline is a Neovim plugin providing Cursor-style inline AI editing. Select code in visual mode, describe a change, and get an inline highlighted edit you can accept or reject.

## Architecture

```
lua/claude-inline/
├── init.lua      # Entry point: calls setup on config, ui, autocmd, base
├── config.lua    # User configuration (keymaps, provider settings)
├── api.lua       # Core logic: API requests, code insertion, highlight management
├── ui.lua        # Floating windows: input prompt, accept/deny helper UI
├── autocmd.lua   # ModeChanged/CursorMoved autocommands for visual mode tracking
├── state.lua     # Shared state: highlight namespaces, extmarks, window/buffer refs
├── utils.lua     # Helpers: visual selection extraction, code region queries
├── prompts.lua   # System prompt for the AI model
└── base.lua      # Keymap bindings setup

plugin/claude-inline.lua  # Plugin loader (sets loaded flag, calls setup)
```

### Data Flow

1. **Visual Selection**: User selects code, `autocmd.lua` captures selection on mode exit
2. **Prompt Input**: `<leader>e` triggers `ui.lua` to show floating input prompt
3. **API Request**: `api.lua` sends selection + prompt to OpenAI via curl
4. **Code Insertion**: Response inserted above old code, both regions highlighted with extmarks
5. **Accept/Reject**: `<leader>y` keeps new code (deletes old), `<leader>n` keeps old (deletes new)

### Key Implementation Details

- **Highlighting**: Uses `nvim_buf_set_extmark` with namespaces `OldCodeHighlight`/`NewCodeHighlight`
- **API**: Calls OpenAI's responses endpoint (`/v1/responses`) with curl via `vim.system`
- **State**: Single shared state table in `state.lua` tracks extmarks, windows, buffers
- **UI Override**: Replaces `vim.ui.input` with custom floating window implementation

## Development

No build system or test framework exists yet. Manual testing:

```lua
-- In Neovim with plugin loaded
:lua require("claude-inline").setup()
-- Select code in visual mode, press <leader>e, enter prompt
-- Use <leader>y to accept or <leader>n to reject
```

## Configuration

```lua
require("claude-inline").setup({
  mappings = {
    open_input = "<leader>e",      -- Trigger prompt from visual mode
    accept_response = "<leader>y", -- Accept generated code (normal mode)
    deny_response = "<leader>n",   -- Reject generated code (normal mode)
  },
  provider = {
    name = "openai",
    model = "gpt-4.1-mini",
  },
})
```

Requires `OPENAI_API_KEY` environment variable.

## Reference: claudecode.nvim

`.cloned-sources/claudecode.nvim/` contains coder/claudecode.nvim as reference material for adding features. This is a mature Neovim plugin with patterns worth borrowing.

### Feature Mapping

| Feature to Add | Reference Location |
|----------------|-------------------|
| Diff view for changes | `lua/claudecode/diff.lua` - native Neovim diff with accept/reject |
| Selection tracking | `lua/claudecode/selection.lua` - debounced tracking, @mentions |
| Terminal integration | `lua/claudecode/terminal/` - snacks.nvim, native, external providers |
| File explorer support | `lua/claudecode/integrations.lua` - nvim-tree, oil, neo-tree, mini.files |
| Logging/debugging | `lua/claudecode/logger.lua` - leveled logging system |
| Configuration schema | `lua/claudecode/config.lua` - defaults with deep merge |

### Key Documentation

- `ARCHITECTURE.md` - Component overview and design decisions
- `PROTOCOL.md` - MCP protocol and WebSocket implementation details
- `DEVELOPMENT.md` - Testing patterns and contribution guidelines
- `CLAUDE.md` - Development commands and quality gates

### Testing Patterns

claudecode.nvim uses busted with comprehensive mocking:

```bash
cd .cloned-sources/claudecode.nvim
make test                           # Full suite with coverage
busted tests/unit/diff_spec.lua    # Single test file
```

Test structure worth copying: `tests/mocks/vim.lua` for vim API mocking, `tests/helpers/setup.lua` for test utilities.

### Code Patterns Worth Adopting

- **Config merging**: `vim.tbl_deep_extend("force", defaults, user_opts)`
- **Async scheduling**: `vim.schedule()` for UI updates from callbacks
- **Namespace isolation**: Separate `nvim_create_namespace` per highlight group
- **Buffer validation**: Always check `nvim_buf_is_valid()` before operations
- **Logging**: Conditional debug output via log level config
