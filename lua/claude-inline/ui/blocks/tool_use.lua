--- Tool use block component for claude-inline.nvim
--- Displays tool invocations as single-line entries
--- Groups child tools under parent Task agents

local state = require 'claude-inline.ui.state'
local buffer = require 'claude-inline.ui.buffer'
local format = require 'claude-inline.ui.blocks.format'

local M = {}

---@class claude-inline.ToolBlock
---@field type 'tool_use'
---@field id string
---@field name string
---@field input table|nil
---@field line number 0-indexed buffer line where this tool is displayed
---@field is_task boolean Whether this is a Task (sub-agent) tool
---@field parent_task_id string|nil ID of parent Task if this is a child tool

--- Get indentation prefix based on task nesting
---@return string
local function get_indent()
  if state.current_task_id then
    return '  '
  end
  return ''
end

--- Display a tool invocation line
---@param tool_id string
---@param tool_name string
---@param input table|nil
function M.show(tool_id, tool_name, input)
  if not buffer.is_valid() then
    return
  end

  local is_task = tool_name == 'Task'
  local line_num = vim.api.nvim_buf_line_count(state.sidebar_buf)

  -- Store block state
  state.content_blocks[tool_id] = {
    type = 'tool_use',
    id = tool_id,
    name = tool_name,
    input = input,
    line = line_num,
    is_task = is_task,
    parent_task_id = state.current_task_id,
  }

  local lines = {}

  if is_task then
    -- Task tool: emit header line, track as current task
    local desc = input and input.description or 'sub-agent'
    table.insert(lines, string.format('[Task: %s]', desc))
    state.current_task_id = tool_id
  else
    -- Regular tool: indent if inside a task
    local indent = get_indent()
    local line = indent .. format.tool_line(tool_name, input) .. ' ...'
    table.insert(lines, line)
  end

  buffer.with_modifiable(function()
    vim.api.nvim_buf_set_lines(state.sidebar_buf, -1, -1, false, lines)
  end)

  buffer.scroll_to_bottom()
end

--- Update tool input as JSON streams in (accumulates partial JSON)
---@param tool_id string
---@param partial_json string
function M.update_input(tool_id, partial_json)
  local block = state.content_blocks[tool_id]
  if not block then
    return
  end

  -- Accumulate JSON for later parsing when result arrives
  block.input_json = (block.input_json or '') .. partial_json

  -- Try to parse and update display with current input
  local ok, parsed = pcall(vim.json.decode, block.input_json)
  if ok and parsed and type(parsed) == 'table' then
    block.input = parsed

    -- Don't update display for Task tools (they show header, not one-liner)
    if block.is_task then
      return
    end

    local indent = block.parent_task_id and '  ' or ''
    local line = indent .. format.tool_line(block.name, parsed) .. ' ...'
    buffer.with_modifiable(function()
      vim.api.nvim_buf_set_lines(state.sidebar_buf, block.line, block.line + 1, false, { line })
    end)
  end
end

--- Mark a tool use as complete (result will update the line with final status)
---@param tool_id string
---@param tool_state? 'success'|'error'
function M.complete(tool_id, tool_state)
  local block = state.content_blocks[tool_id]
  if not block then
    return
  end

  block.state = tool_state or 'success'

  -- Parse final input JSON if not already done
  if block.input_json and not block.input then
    local ok, parsed = pcall(vim.json.decode, block.input_json)
    if ok then
      block.input = parsed
    end
  end
end

--- Collapse is a no-op for one-line display
---@param tool_id string
function M.collapse(tool_id)
  -- Single-line format doesn't need folding
end

return M
