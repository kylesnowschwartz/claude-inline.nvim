--- Block registry for claude-inline.nvim
--- Common utilities for all content block types

local state = require 'claude-inline.ui.state'
local buffer = require 'claude-inline.ui.buffer'

local M = {}

-- Lazy-load block modules to avoid circular dependencies
-- These will be populated when accessed
M.message = nil
M.tool_use = nil
M.tool_result = nil

--- Get the message block at cursor position
---@return MessageBlock|nil
function M.get_at_cursor()
  if not buffer.is_sidebar_open() then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(state.sidebar_win)
  local cursor_line = cursor[1] - 1 -- Convert to 0-indexed
  local line_count = vim.api.nvim_buf_line_count(state.sidebar_buf)

  -- With point extmarks, block end = next block's start (or buffer end)
  for i, block in ipairs(state.message_blocks) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(state.sidebar_buf, state.MESSAGE_NS, block.id, {})
    if mark and #mark >= 1 then
      local start_row = mark[1]
      local end_row

      -- End is either next block's start or buffer end
      if i < #state.message_blocks then
        local next_mark = vim.api.nvim_buf_get_extmark_by_id(state.sidebar_buf, state.MESSAGE_NS, state.message_blocks[i + 1].id, {})
        end_row = next_mark and next_mark[1] - 1 or line_count - 1
      else
        end_row = line_count - 1
      end

      if cursor_line >= start_row and cursor_line <= end_row then
        return block
      end
    end
  end
  return nil
end

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
  end
  state.message_blocks = {}

  buffer.with_modifiable(function()
    vim.api.nvim_buf_set_lines(state.sidebar_buf, 0, -1, false, {})
  end)

  state.current_message_open = false
  state.content_blocks = {}
  state.task_stack = {}
end

return M
