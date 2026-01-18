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
    -- Pop this task from stack (find and remove it)
    for i = #state.task_stack, 1, -1 do
      if state.task_stack[i] == tool_use_id then
        table.remove(state.task_stack, i)
        break
      end
    end

    -- Task completion: emit summary line at current indent level
    local indent = string.rep('  ', #state.task_stack)
    local short_id = tool_use_id:sub(-6)
    local line = indent .. '[Task ' .. short_id .. '] ' .. status .. meta_str
    buffer.with_modifiable(function()
      vim.api.nvim_buf_set_lines(state.sidebar_buf, -1, -1, false, { line })
    end)
  else
    -- Regular tool: update line in-place with same indent as when created
    -- Count how deep the parent was in the stack when this tool was created
    local depth = 0
    if tool_block.parent_task_id then
      -- Find parent's depth by counting how many tasks are above it in stack
      for i, tid in ipairs(state.task_stack) do
        if tid == tool_block.parent_task_id then
          depth = i
          break
        end
      end
      -- If parent not in stack anymore, use stored line's indent
      if depth == 0 then
        depth = 1 -- minimum indent for child of a task
      end
    end
    local indent = string.rep('  ', depth)
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
