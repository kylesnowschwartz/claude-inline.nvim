--- Tool use block component for claude-inline.nvim
--- Displays tool invocations with streaming parameter updates

local state = require 'claude-inline.ui.state'
local buffer = require 'claude-inline.ui.buffer'

local M = {}

--- Show a tool use block in the sidebar
--- Called when content_block_start with type="tool_use" is received
---@param tool_id string The unique tool use ID
---@param tool_name string The tool name (e.g., "read_file", "bash")
---@param input table|nil Initial input parameters (may be empty during streaming)
function M.show(tool_id, tool_name, input)
  if not buffer.is_valid() then
    return
  end

  -- Store the content block state
  local line_count = vim.api.nvim_buf_line_count(state.sidebar_buf)
  state.content_blocks[tool_id] = {
    type = 'tool_use',
    id = tool_id,
    name = tool_name,
    start_line = line_count, -- 0-indexed
    end_line = nil,
    folded = false,
    state = 'running',
    input_json = '',
  }
  state.current_tool_id = tool_id

  -- Render the tool header and initial content
  local header = string.format('> [tool: %s] running...', tool_name)
  local lines = { header, '> +--' }

  -- If we have initial input, format it
  if input and next(input) then
    for key, value in pairs(input) do
      local value_str = type(value) == 'string' and value or vim.json.encode(value)
      -- Truncate long values
      if #value_str > 60 then
        value_str = value_str:sub(1, 57) .. '...'
      end
      table.insert(lines, string.format('> |   %s: %s', key, value_str))
    end
  end

  table.insert(lines, '> +--')

  buffer.with_modifiable(function()
    vim.api.nvim_buf_set_lines(state.sidebar_buf, -1, -1, false, lines)
  end)

  buffer.scroll_to_bottom()
end

--- Update tool input as JSON streams in
--- Called on content_block_delta with type="input_json_delta"
---@param tool_id string The tool use ID
---@param partial_json string Partial JSON fragment to accumulate
function M.update_input(tool_id, partial_json)
  local block = state.content_blocks[tool_id]
  if not block then
    return
  end

  -- Accumulate the JSON string
  block.input_json = (block.input_json or '') .. partial_json

  -- Try to parse and display what we have so far
  -- This is best-effort - partial JSON may not parse
  local ok, input = pcall(vim.json.decode, block.input_json)
  if ok and input and type(input) == 'table' then
    -- Re-render the tool block with current input
    local header = string.format('> [tool: %s] running...', block.name)
    local lines = { header, '> +--' }

    for key, value in pairs(input) do
      local value_str = type(value) == 'string' and value or vim.json.encode(value)
      if #value_str > 60 then
        value_str = value_str:sub(1, 57) .. '...'
      end
      table.insert(lines, string.format('> |   %s: %s', key, value_str))
    end

    table.insert(lines, '> +--')

    buffer.with_modifiable(function()
      vim.api.nvim_buf_set_lines(state.sidebar_buf, block.start_line, -1, false, lines)
    end)

    buffer.scroll_to_bottom()
  end
end

--- Mark a tool use as complete
--- Called on content_block_stop for tool_use blocks
---@param tool_id string The tool use ID
---@param tool_state? 'success'|'error' Final state (default: 'success')
function M.complete(tool_id, tool_state)
  local block = state.content_blocks[tool_id]
  if not block then
    return
  end

  block.state = tool_state or 'success'
  block.end_line = vim.api.nvim_buf_line_count(state.sidebar_buf) - 1

  -- Parse final input JSON
  local input = {}
  if block.input_json and block.input_json ~= '' then
    local ok, parsed = pcall(vim.json.decode, block.input_json)
    if ok then
      input = parsed
    end
  end

  -- Re-render with final state
  local status = block.state == 'success' and 'done' or 'error'
  local header = string.format('> [tool: %s] %s', block.name, status)
  local lines = { header, '> +--' }

  if input and next(input) then
    for key, value in pairs(input) do
      local value_str = type(value) == 'string' and value or vim.json.encode(value)
      if #value_str > 60 then
        value_str = value_str:sub(1, 57) .. '...'
      end
      table.insert(lines, string.format('> |   %s: %s', key, value_str))
    end
  end

  table.insert(lines, '> +--')
  table.insert(lines, '') -- Blank line after tool block

  buffer.with_modifiable(function()
    vim.api.nvim_buf_set_lines(state.sidebar_buf, block.start_line, -1, false, lines)
  end)

  -- Clear current tool tracking
  if state.current_tool_id == tool_id then
    state.current_tool_id = nil
  end

  buffer.scroll_to_bottom()
end

--- Collapse a tool use block
---@param tool_id string The tool use ID
function M.collapse(tool_id)
  local block = state.content_blocks[tool_id]
  if not block or block.folded then
    return
  end

  if buffer.is_sidebar_open() then
    vim.schedule(function()
      pcall(function()
        -- Move to tool header line and close fold
        vim.api.nvim_win_set_cursor(state.sidebar_win, { block.start_line + 1, 0 })
        vim.api.nvim_win_call(state.sidebar_win, function()
          vim.cmd 'normal! zc'
        end)
        buffer.scroll_to_bottom()
      end)
    end)
  end

  block.folded = true
end

return M
