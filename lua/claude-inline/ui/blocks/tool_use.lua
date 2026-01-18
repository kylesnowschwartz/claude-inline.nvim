--- Tool use block component for claude-inline.nvim
--- Displays tool invocations as single-line entries
--- Uses extmarks for position tracking to handle parallel Tasks

local state = require 'claude-inline.ui.state'
local buffer = require 'claude-inline.ui.buffer'
local format = require 'claude-inline.ui.blocks.format'

local M = {}

---@class claude-inline.ToolBlock
---@field type 'tool_use'
---@field id string
---@field name string
---@field input table|nil
---@field extmark_id number|nil Extmark for position tracking
---@field is_task boolean Whether this is a Task (sub-agent) tool
---@field parent_task_id string|nil ID of parent Task if this is a child tool
---@field child_count number Number of children inserted after this Task

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

--- Display a tool invocation line
---@param tool_id string
---@param tool_name string
---@param input table|nil
---@param parent_tool_use_id string|nil Explicit parent from message (nil for top-level)
function M.show(tool_id, tool_name, input, parent_tool_use_id)
  if not buffer.is_valid() then
    return
  end

  local is_task = tool_name == 'Task'
  local parent_task_id = parent_tool_use_id -- Use explicit parent, not stack

  -- Create block record
  local block = {
    type = 'tool_use',
    id = tool_id,
    name = tool_name,
    input = input,
    extmark_id = nil,
    is_task = is_task,
    parent_task_id = parent_task_id,
    child_count = 0,
  }

  local insert_line
  local line_text

  if is_task then
    -- Task: render header, track position with extmark
    local desc = input and input.description or 'sub-agent'
    local short_id = tool_id:sub(-6)
    line_text = string.format('[Task %s: %s]', short_id, desc)

    -- Find insert position: after parent's children, or at end
    if parent_task_id then
      local parent = state.content_blocks[parent_task_id]
      if parent and parent.extmark_id then
        local parent_line = get_extmark_line(parent.extmark_id)
        if parent_line then
          insert_line = parent_line + 1 + parent.child_count
          parent.child_count = parent.child_count + 1
        end
      end
    end

    -- Default: append at end
    if not insert_line then
      insert_line = vim.api.nvim_buf_line_count(state.sidebar_buf)
    end

    -- Clamp to buffer bounds (child_count can become stale with parallel Tasks)
    local max_line = vim.api.nvim_buf_line_count(state.sidebar_buf)
    if insert_line > max_line then
      insert_line = max_line
    end
    -- No stack push needed - parent_tool_use_id from messages handles nesting
  else
    -- Regular tool: render with indent if has parent
    local indent = parent_task_id and '  ' or ''
    line_text = indent .. format.tool_line(tool_name, input) .. ' ...'

    -- Find insert position: after parent's children
    if parent_task_id then
      local parent = state.content_blocks[parent_task_id]
      if parent and parent.extmark_id then
        local parent_line = get_extmark_line(parent.extmark_id)
        if parent_line then
          insert_line = parent_line + 1 + parent.child_count
          parent.child_count = parent.child_count + 1
        end
      end
    end

    -- Default: append at end
    if not insert_line then
      insert_line = vim.api.nvim_buf_line_count(state.sidebar_buf)
    end

    -- Clamp to buffer bounds (child_count can become stale with parallel Tasks)
    local max_line = vim.api.nvim_buf_line_count(state.sidebar_buf)
    if insert_line > max_line then
      insert_line = max_line
    end
  end

  -- Insert line at calculated position
  buffer.with_modifiable(function()
    vim.api.nvim_buf_set_lines(state.sidebar_buf, insert_line, insert_line, false, { line_text })
  end)

  -- Create extmark at the inserted line with right_gravity=true (default) so it moves
  -- when lines are inserted before it. We use nvim_buf_set_text for updates to avoid drift.
  block.extmark_id = vim.api.nvim_buf_set_extmark(state.sidebar_buf, state.TOOL_NS, insert_line, 0, {})

  state.content_blocks[tool_id] = block
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

  -- Accumulate JSON for later parsing
  block.input_json = (block.input_json or '') .. partial_json

  -- Try to parse and update stored input
  local ok, parsed = pcall(vim.json.decode, block.input_json)
  if ok and parsed and type(parsed) == 'table' then
    block.input = parsed

    -- Update display using extmark position
    if block.extmark_id then
      local line_num = get_extmark_line(block.extmark_id)
      if line_num then
        local line_text
        if block.is_task then
          -- Update Task header with description
          local desc = parsed.description or 'sub-agent'
          local short_id = tool_id:sub(-6)
          line_text = string.format('[Task %s: %s]', short_id, desc)
        else
          -- Update tool line
          local indent = block.parent_task_id and '  ' or ''
          line_text = indent .. format.tool_line(block.name, parsed) .. ' ...'
        end

        -- Use nvim_buf_set_text to replace line content without delete+insert,
        -- which would cause extmarks with right_gravity=true to drift
        buffer.with_modifiable(function()
          local old_line = vim.api.nvim_buf_get_lines(state.sidebar_buf, line_num, line_num + 1, false)[1] or ''
          vim.api.nvim_buf_set_text(state.sidebar_buf, line_num, 0, line_num, #old_line, { line_text })
        end)
      end
    end
  end
end

--- Mark a tool use as complete (result will update with final status)
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
