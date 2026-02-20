--- Tool use block component for claude-inline.nvim
--- Displays tool invocations as single-line entries
--- Uses extmarks for position tracking to handle parallel Tasks

local state = require("claude-inline.ui.state")
local buffer = require("claude-inline.ui.buffer")
local format = require("claude-inline.ui.blocks.format")

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

--- Display a tool invocation line
---@param tool_id string
---@param tool_name string
---@param input table|nil
---@param parent_tool_use_id string|nil Explicit parent from message (nil for top-level)
function M.show(tool_id, tool_name, input, parent_tool_use_id)
  if not buffer.is_valid() then
    return
  end

  local is_task = tool_name == "Task"
  local parent_task_id = parent_tool_use_id -- Use explicit parent, not stack

  -- Create block record
  local block = {
    type = "tool_use",
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
    local desc = input and input.description or "sub-agent"
    local short_id = tool_id:sub(-6)
    line_text = string.format("[Task %s: %s]", short_id, desc)
  else
    -- Regular tool: render with indent if has parent
    local indent = parent_task_id and "  " or ""
    line_text = indent .. format.tool_line(tool_name, input) .. " ..."
  end

  -- Calculate insert position using shared helper
  insert_line = buffer.get_child_insert_line(parent_task_id, true)

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

return M
