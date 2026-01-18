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

return M
