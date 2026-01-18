--- Buffer utilities for claude-inline.nvim
--- Shared helpers for sidebar buffer operations

local state = require 'claude-inline.ui.state'

local M = {}

--- Check if sidebar buffer is valid
---@return boolean
function M.is_valid()
  return state.sidebar_buf ~= nil and vim.api.nvim_buf_is_valid(state.sidebar_buf)
end

--- Check if sidebar window is open and valid
---@return boolean
function M.is_sidebar_open()
  return state.sidebar_win ~= nil and vim.api.nvim_win_is_valid(state.sidebar_win)
end

--- Execute a function with the sidebar buffer temporarily modifiable
---@param fn function Function to execute
---@return any Result from fn
function M.with_modifiable(fn)
  if not M.is_valid() then
    return
  end
  vim.api.nvim_set_option_value('modifiable', true, { buf = state.sidebar_buf })
  local ok, result = pcall(fn)
  vim.api.nvim_set_option_value('modifiable', false, { buf = state.sidebar_buf })
  if not ok then
    error(result)
  end
  return result
end

--- Scroll sidebar window to bottom if visible
function M.scroll_to_bottom()
  if M.is_sidebar_open() then
    local line_count = vim.api.nvim_buf_line_count(state.sidebar_buf)
    vim.api.nvim_win_set_cursor(state.sidebar_win, { line_count, 0 })
  end
end

--- Get current line position from a tool extmark
---@param extmark_id number
---@return number|nil 0-indexed line number
function M.get_tool_extmark_line(extmark_id)
  if not M.is_valid() then
    return nil
  end
  local mark = vim.api.nvim_buf_get_extmark_by_id(state.sidebar_buf, state.TOOL_NS, extmark_id, {})
  if mark and #mark >= 1 then
    return mark[1]
  end
  return nil
end

--- Calculate insert position for content under a parent Task block
---@param parent_id string|nil Parent tool/task ID
---@param increment_child_count boolean Whether to increment parent's child_count
---@return number 0-indexed line number for insertion
function M.get_child_insert_line(parent_id, increment_child_count)
  local insert_line = nil
  if parent_id then
    local parent = state.content_blocks[parent_id]
    if parent and parent.extmark_id then
      local parent_line = M.get_tool_extmark_line(parent.extmark_id)
      if parent_line then
        insert_line = parent_line + 1 + (parent.child_count or 0)
        if increment_child_count then
          parent.child_count = (parent.child_count or 0) + 1
        end
      end
    end
  end
  if not insert_line then
    insert_line = vim.api.nvim_buf_line_count(state.sidebar_buf)
  end
  -- Clamp to buffer bounds (child_count can become stale with parallel Tasks)
  local max_line = vim.api.nvim_buf_line_count(state.sidebar_buf)
  if insert_line > max_line then
    insert_line = max_line
  end
  return insert_line
end

return M
