--- Tool result block component for claude-inline.nvim
--- Displays tool execution results with metadata

local state = require 'claude-inline.ui.state'
local buffer = require 'claude-inline.ui.buffer'

local M = {}

--- Show a tool result block in the sidebar
--- Called when processing tool_result content blocks from user messages
---@param tool_use_id string The ID of the tool_use this result is for
---@param content string The result content
---@param is_error boolean|nil Whether this is an error result
---@param metadata table|nil Optional metadata (durationMs, numFiles, exitCode, truncated)
function M.show(tool_use_id, content, is_error, metadata)
  if not buffer.is_valid() then
    return
  end

  -- Find the corresponding tool_use block for the name
  local tool_block = state.content_blocks[tool_use_id]
  local tool_name = tool_block and tool_block.name or 'unknown'

  -- Store the content block state
  local line_count = vim.api.nvim_buf_line_count(state.sidebar_buf)
  local result_id = 'result_' .. tool_use_id
  state.content_blocks[result_id] = {
    type = 'tool_result',
    id = result_id,
    name = tool_name,
    start_line = line_count, -- 0-indexed
    end_line = nil,
    folded = false,
    state = is_error and 'error' or 'success',
  }

  -- Format the result header with metadata
  local header_parts = {}
  if metadata then
    -- For file operations, show file count
    if metadata.numFiles then
      table.insert(header_parts, string.format('%d files', metadata.numFiles))
    end
    -- For bash commands, show exit code if non-zero
    if metadata.exitCode and metadata.exitCode ~= 0 then
      table.insert(header_parts, string.format('exit %d', metadata.exitCode))
    end
    -- Show duration
    if metadata.durationMs then
      if metadata.durationMs >= 1000 then
        table.insert(header_parts, string.format('%.1fs', metadata.durationMs / 1000))
      else
        table.insert(header_parts, string.format('%dms', metadata.durationMs))
      end
    end
    -- Note if truncated
    if metadata.truncated then
      table.insert(header_parts, 'truncated')
    end
  end

  local result_status = is_error and 'error' or 'success'
  local header
  if #header_parts > 0 then
    header = string.format('> [result: %s] %s (%s)', tool_name, result_status, table.concat(header_parts, ', '))
  else
    header = string.format('> [result: %s] %s', tool_name, result_status)
  end
  local lines = { header, '> +--' }

  -- Summarize the content
  local content_lines = vim.split(content or '', '\n', { plain = true })
  local line_count_display = #content_lines

  if line_count_display > 5 then
    -- Show summary for long results
    table.insert(lines, string.format('> |   (%d lines)', line_count_display))
    -- Show first 3 lines as preview
    for i = 1, math.min(3, #content_lines) do
      local preview_line = content_lines[i]:sub(1, 55)
      if #content_lines[i] > 55 then
        preview_line = preview_line .. '...'
      end
      table.insert(lines, '> |   ' .. preview_line)
    end
    if #content_lines > 3 then
      table.insert(lines, '> |   ...')
    end
  else
    -- Show full content for short results
    for _, line in ipairs(content_lines) do
      local display_line = line:sub(1, 60)
      if #line > 60 then
        display_line = display_line .. '...'
      end
      table.insert(lines, '> |   ' .. display_line)
    end
  end

  table.insert(lines, '> +--')
  table.insert(lines, '') -- Blank line after result block

  buffer.with_modifiable(function()
    vim.api.nvim_buf_set_lines(state.sidebar_buf, -1, -1, false, lines)
  end)

  state.content_blocks[result_id].end_line = vim.api.nvim_buf_line_count(state.sidebar_buf) - 1

  buffer.scroll_to_bottom()
end

--- Collapse a tool result block
---@param tool_use_id string The tool use ID (result ID will be derived)
function M.collapse(tool_use_id)
  local result_id = 'result_' .. tool_use_id
  local block = state.content_blocks[result_id]
  if not block or block.folded then
    return
  end

  if buffer.is_sidebar_open() then
    vim.schedule(function()
      pcall(function()
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
