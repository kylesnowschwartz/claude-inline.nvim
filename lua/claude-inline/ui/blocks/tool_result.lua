--- Tool result block component for claude-inline.nvim
--- Updates tool line in-place with status and metadata
--- Uses extmarks for position tracking

local state = require 'claude-inline.ui.state'
local buffer = require 'claude-inline.ui.buffer'
local format = require 'claude-inline.ui.blocks.format'

local M = {}

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
    -- Use tool's own ID to find position (not increment, just read)
    local insert_line = buffer.get_child_insert_line(tool_use_id, false)

    -- Completion line with result content
    local short_id = tool_use_id:sub(-6)
    local completion = '[Task ' .. short_id .. '] ' .. status .. meta_str

    -- Build lines to insert: completion line, result content (if any), blank separator
    local lines_to_insert = { completion }

    -- Add Task result content if present (the agent's final answer)
    -- Content can be a string or a table of content blocks [{type: "text", text: "..."}]
    if content then
      local text_content = content
      if type(content) == 'table' then
        -- Extract text from content blocks
        local texts = {}
        for _, block in ipairs(content) do
          if block.type == 'text' and block.text then
            table.insert(texts, block.text)
          end
        end
        text_content = table.concat(texts, '\n')
      end

      if text_content and text_content ~= '' then
        -- Indent result content
        local result_lines = vim.split(text_content, '\n', { plain = true })
        for _, line in ipairs(result_lines) do
          table.insert(lines_to_insert, '  ' .. line)
        end
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
      local line_num = buffer.get_tool_extmark_line(tool_block.extmark_id)
      if line_num then
        buffer.with_modifiable(function()
          vim.api.nvim_buf_set_lines(state.sidebar_buf, line_num, line_num + 1, false, { line })
        end)
      end
    end
  end
end

return M
