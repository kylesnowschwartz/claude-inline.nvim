--- Tool result block component for claude-inline.nvim
--- Updates tool line in-place with status and metadata
--- Uses extmarks for position tracking

local state = require 'claude-inline.ui.state'
local buffer = require 'claude-inline.ui.buffer'
local format = require 'claude-inline.ui.blocks.format'

local M = {}

--- Get current line position from extmark
---@param extmark_id number
---@return number|nil 0-indexed line number
local function get_extmark_line(extmark_id)
  if not buffer.is_valid() then
    return nil
  end
  local mark = vim.api.nvim_buf_get_extmark_by_id(state.sidebar_buf, state.TOOL_NS, extmark_id, {})
  if mark and #mark >= 1 then
    return mark[1]
  end
  return nil
end

--- Update the tool line with result status
---@param tool_use_id string The ID of the tool_use this result is for
---@param content string|nil The result content (shown for Task agents)
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
    -- Task completion: insert completion line after children
    -- No stack manipulation needed - parent_tool_use_id from messages handles nesting

    -- Find insert position: after task header + all its children
    local insert_line
    if tool_block.extmark_id then
      local task_line = get_extmark_line(tool_block.extmark_id)
      if task_line then
        insert_line = task_line + 1 + tool_block.child_count
      end
    end

    -- Fallback: append at end
    if not insert_line then
      insert_line = vim.api.nvim_buf_line_count(state.sidebar_buf)
    end

    -- Clamp to buffer bounds (child_count can become stale with parallel Tasks)
    local max_line = vim.api.nvim_buf_line_count(state.sidebar_buf)
    if insert_line > max_line then
      insert_line = max_line
    end

    -- Completion line with result content
    local short_id = tool_use_id:sub(-6)
    local completion = '[Task ' .. short_id .. '] ' .. status .. meta_str

    -- Build lines to insert: completion line, result content (if any), blank separator
    local lines_to_insert = { completion }

    -- Add Task result content if present (the agent's final answer)
    if content and content ~= '' then
      -- Indent result content and wrap long lines
      local result_lines = vim.split(content, '\n', { plain = true })
      for _, line in ipairs(result_lines) do
        table.insert(lines_to_insert, '  ' .. line)
      end
    end

    -- Blank separator after Task block
    table.insert(lines_to_insert, '')

    buffer.with_modifiable(function()
      vim.api.nvim_buf_set_lines(state.sidebar_buf, insert_line, insert_line, false, lines_to_insert)
    end)
  else
    -- Regular tool: update line in-place using extmark position
    local indent = tool_block.parent_task_id and '  ' or ''
    local line = indent .. format.tool_line(tool_block.name, tool_block.input) .. ' ' .. status .. meta_str

    if tool_block.extmark_id then
      local line_num = get_extmark_line(tool_block.extmark_id)
      if line_num then
        buffer.with_modifiable(function()
          vim.api.nvim_buf_set_lines(state.sidebar_buf, line_num, line_num + 1, false, { line })
        end)
      end
    end
  end
end

--- Collapse is a no-op for one-line display
---@param tool_use_id string
function M.collapse(tool_use_id)
  -- Single-line format doesn't need folding
end

return M
