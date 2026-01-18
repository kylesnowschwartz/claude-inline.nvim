--- Block registry for claude-inline.nvim
--- Common utilities for all content block types

local state = require 'claude-inline.ui.state'
local buffer = require 'claude-inline.ui.buffer'

local M = {}

--- Get all message blocks in the conversation
---@return MessageBlock[]
function M.get_all()
  return vim.deepcopy(state.message_blocks)
end

--- Clear all blocks and reset state
function M.clear_all()
  -- Clear extmarks and reset block tracking
  if buffer.is_valid() then
    vim.api.nvim_buf_clear_namespace(state.sidebar_buf, state.MESSAGE_NS, 0, -1)
    vim.api.nvim_buf_clear_namespace(state.sidebar_buf, state.TOOL_NS, 0, -1)
  end
  state.message_blocks = {}

  buffer.with_modifiable(function()
    vim.api.nvim_buf_set_lines(state.sidebar_buf, 0, -1, false, {})
  end)

  state.current_message_open = false
  state.content_blocks = {}
end

return M
