# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Active Development Context

@.agent-history/context-packet-20260111.md

## Project Overview

claude-inline.nvim is a Neovim plugin providing Cursor-style inline AI editing via Claude Code CLI. Select code in visual mode, open the Claude terminal, describe a change, and get a native Neovim diff you can accept (`:w`) or reject (close buffer).

## Architecture

```
lua/claude-inline/
├── init.lua       # Entry point: setup, WebSocket server, MCP JSON-RPC routing
├── config.lua     # User configuration (keymaps only)
├── api.lua        # DEPRECATED stub (OpenAI code removed)
├── ui.lua         # Visual mode selection hint
├── autocmd.lua    # ModeChanged autocommands, selection capture, broadcast
├── state.lua      # Selection state for MCP tools
├── utils.lua      # Visual selection extraction
├── base.lua       # Keymap bindings (toggle_terminal only)
├── diff.lua       # Native Neovim diff with blocking accept/reject
├── lockfile.lua   # Lock file discovery for Claude Code CLI
├── terminal.lua   # Terminal sidebar running Claude Code CLI
├── websocket/     # WebSocket server implementation
│   ├── init.lua   # Server lifecycle
│   ├── client.lua # Client management
│   └── ...        # Frame handling, handshake
└── tools/         # MCP tools for Claude Code
    ├── init.lua               # Tool registry
    ├── get_current_selection.lua
    ├── get_latest_selection.lua
    └── open_diff.lua

plugin/claude-inline.lua  # Plugin loader
```

### Data Flow

1. **Visual Selection**: User selects code, exits to normal mode
2. **Selection Capture**: `autocmd.lua` captures selection, stores in `state.lua`, broadcasts `selection/changed` to Claude Code
3. **Terminal**: `<leader>cc` opens terminal sidebar with Claude Code CLI
4. **Claude Interaction**: User asks Claude to modify `@selection`
5. **Diff View**: Claude calls `openDiff` MCP tool, native Neovim diff appears
6. **Accept/Reject**: `:w` accepts (returns `FILE_SAVED`), close buffer rejects (returns `DIFF_REJECTED`)

### Key Implementation Details

- **WebSocket Server**: Pure Lua RFC 6455 implementation for Claude Code CLI communication
- **MCP Tools**: JSON-RPC 2.0 handlers for `getCurrentSelection`, `getLatestSelection`, `openDiff`
- **Lock File**: `~/.claude/ide/[port].lock` allows Claude CLI to discover the server
- **Blocking Diff**: Coroutine-based blocking in `openDiff` until user accepts/rejects

## Development

### Running Tests

```bash
# Run all unit tests (headless Neovim)
nvim --headless -l tests/run_tests.lua

# Run E2E smoke test
nvim --headless -u NONE -c "set runtimepath+=." -l tests/e2e/smoke_test_spec.lua

# Syntax check all Lua files
for f in lua/claude-inline/*.lua; do luac -p "$f"; done
```

### Test Infrastructure

Tests follow claudecode.nvim patterns using busted-style structure:

```
tests/
├── busted_setup.lua           # Test setup: vim mock, expect() helpers, JSON utils
├── mocks/
│   └── vim.lua                # Comprehensive vim API mock
├── run_tests.lua              # Headless test runner
├── unit/                      # Unit tests (isolated, mocked)
│   └── tools/
│       ├── get_current_selection_spec.lua
│       ├── get_latest_selection_spec.lua
│       ├── open_diff_spec.lua
│       └── tools_init_spec.lua
└── e2e/                       # End-to-end tests (real plugin)
    └── smoke_test_spec.lua
```

### Writing Tests

**File naming**: `*_spec.lua` for all test files

**Required setup**: Always require the busted setup at the top:

```lua
require 'tests.busted_setup'
```

**Test structure**: Use nested `describe()` for context, `it()` for assertions:

```lua
require 'tests.busted_setup'

describe('Module Name', function()
  local module_under_test

  before_each(function()
    -- Clear cached modules to ensure isolation
    package.loaded['claude-inline.module'] = nil

    -- Set up mocks
    _G.vim.api.nvim_get_current_buf = spy.new(function()
      return 1
    end)

    -- Load module after mocks are configured
    module_under_test = require('claude-inline.module')
  end)

  after_each(function()
    -- Clean up
    package.loaded['claude-inline.module'] = nil
  end)

  describe('specific feature', function()
    it('should do something specific', function()
      local result = module_under_test.some_function()

      expect(result).to_be_table()
      expect(result.success).to_be_true()
    end)

    it('should handle edge case', function()
      -- Test edge case
    end)
  end)
end)
```

**Assertion helpers** (from `busted_setup.lua`):

```lua
expect(value).to_be(expected)        -- Strict equality
expect(value).to_be_nil()
expect(value).to_be_true()
expect(value).to_be_false()
expect(value).to_be_table()
expect(value).to_be_string()
expect(value).to_be_function()
expect(value).not_to_be_nil()
expect(value).to_be_at_least(n)

assert_contains(str_or_table, pattern)  -- String contains or table has element
```

**JSON helpers** for MCP responses:

```lua
local parsed = json_decode(result.content[1].text)
expect(parsed.success).to_be_true()
```

**Mocking vim APIs**:

```lua
-- Use spy.new for tracked mocks
_G.vim.api.nvim_buf_get_name = spy.new(function(bufnr)
  return '/test/file.lua'
end)

-- Mock module dependencies via package.loaded
local mock_state = { selected_text = 'test' }
package.loaded['claude-inline.state'] = mock_state
```

### Test Principles

- **Isolation**: Each test clears `package.loaded` to avoid state leakage
- **Mocking**: Mock vim APIs and module dependencies, not the module under test
- **Coverage**: Test both happy paths and error cases
- **Naming**: Descriptive `it()` descriptions that read as specifications
- **MCP Format**: Tool tests verify the `{content: [{type: "text", text: JSON}]}` structure

## Configuration

```lua
require("claude-inline").setup({
  mappings = {
    toggle_terminal = "<leader>cc",  -- Toggle Claude terminal sidebar
  },
})
```

No API keys required - Claude Code CLI handles authentication.

## Reference: claudecode.nvim

`.cloned-sources/claudecode.nvim/` contains coder/claudecode.nvim as reference material. This is a mature Neovim plugin implementing the same MCP protocol.

### Key Documentation

- `ARCHITECTURE.md` - Component overview and design decisions
- `PROTOCOL.md` - MCP protocol and WebSocket implementation details
- `CLAUDE.md` - Development commands and quality gates

### Code Patterns

- **Config merging**: `vim.tbl_deep_extend("force", defaults, user_opts)`
- **Async scheduling**: `vim.schedule()` for UI updates from callbacks
- **Buffer validation**: Always check `nvim_buf_is_valid()` before operations
- **MCP format**: All tools return `{content: [{type: "text", text: JSON}]}`
