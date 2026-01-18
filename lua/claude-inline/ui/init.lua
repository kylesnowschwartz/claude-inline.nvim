--- UI components for claude-inline.nvim
--- Sidebar, input prompt, and loading spinner
local M = {}

local state = require 'claude-inline.ui.state'
local fold = require 'claude-inline.ui.fold'
local sidebar = require 'claude-inline.ui.sidebar'
local input = require 'claude-inline.ui.input'
local loading = require 'claude-inline.ui.loading'
local message = require 'claude-inline.ui.blocks.message'
local tool_use = require 'claude-inline.ui.blocks.tool_use'
local tool_result = require 'claude-inline.ui.blocks.tool_result'
local blocks = require 'claude-inline.ui.blocks'

-- Re-export state for external access (debugging, etc.)
M._state = state

-- Re-export fold functions for vim option strings (v:lua.require'...'.foldexpr())
M.foldexpr = fold.foldexpr
M.foldtext = fold.foldtext

--- Setup UI module with configuration
---@param config table
function M.setup(config)
  state.config = config
end

-- Re-export sidebar functions
M.is_sidebar_open = sidebar.is_open
M.show_sidebar = sidebar.show
M.hide_sidebar = sidebar.hide
M.toggle_sidebar = sidebar.toggle

-- Re-export message functions
M.append_message = message.append
M.update_last_message = message.update_last
M.close_current_message = message.close_current

-- Re-export tool use functions
M.show_tool_use = tool_use.show
M.update_tool_input = tool_use.update_input
M.complete_tool = tool_use.complete
M.collapse_tool = tool_use.collapse

-- Re-export tool result functions
M.show_tool_result = tool_result.show
M.collapse_tool_result = tool_result.collapse

-- Re-export block utility functions
M.clear = blocks.clear_all
M.get_block_at_cursor = blocks.get_at_cursor
M.get_all_blocks = blocks.get_all

-- Re-export input function
M.show_input = input.show

-- Setup loading callbacks (must be after message functions are defined)
loading.setup_callbacks(M.append_message, M.update_last_message)

-- Re-export loading functions
M.show_loading = loading.show
M.hide_loading = loading.hide

--- Cleanup all UI elements
function M.cleanup()
  M.hide_loading()
  input.close()
  blocks.clear_all()
end

--- Collapse all message blocks in the sidebar
function M.fold_all()
  fold.fold_all()
  for _, block in ipairs(M._state.message_blocks) do
    block.folded = true
  end
end

--- Expand all message blocks in the sidebar
function M.unfold_all()
  fold.unfold_all()
  for _, block in ipairs(M._state.message_blocks) do
    block.folded = false
  end
end

return M
