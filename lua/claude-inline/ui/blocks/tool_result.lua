--- Tool result block component for claude-inline.nvim
--- Updates tool line in-place with status and metadata
--- Handles Task completion with summary line

local state = require 'claude-inline.ui.state'
local buffer = require 'claude-inline.ui.buffer'
local format = require 'claude-inline.ui.blocks.format'

local M = {}

--- Update the tool line with result status
---@param tool_use_id string The ID of the tool_use this result is for
---@param content string|nil The result content (unused in one-line display)
---@param is_error boolean|nil Whether this is an error result
---@param metadata table|nil Optional metadata from tool_use_result
function M.show(tool_use_id, content, is_error, metadata)
  local tool_block = state.content_blocks[tool_use_id]
  if not tool_block then
    return
  end

  local status = is_error and '✗' or '✓'
  local meta_str = format.metadata_suffix(metadata)

  if tool_block.is_task then
    -- Task completion: emit summary line and clear current task
    local line = '[Task] ' .. status .. meta_str
    buffer.with_modifiable(function()
      vim.api.nvim_buf_set_lines(state.sidebar_buf, -1, -1, false, { line })
    end)

    -- Clear task tracking so subsequent tools aren't indented
    if state.current_task_id == tool_use_id then
      state.current_task_id = nil
    end
  else
    -- Regular tool: update line in-place
    local indent = tool_block.parent_task_id and '  ' or ''
    local line = indent .. format.tool_line(tool_block.name, tool_block.input) .. ' ' .. status .. meta_str

    buffer.with_modifiable(function()
      vim.api.nvim_buf_set_lines(state.sidebar_buf, tool_block.line, tool_block.line + 1, false, { line })
    end)
  end
end

--- Collapse is a no-op for one-line display
---@param tool_use_id string
function M.collapse(tool_use_id)
  -- Single-line format doesn't need folding
end

return M
