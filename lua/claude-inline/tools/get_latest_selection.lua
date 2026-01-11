--- Tool implementation for getting the latest text selection.
--- Returns the most recent selection, even if not in the active editor.

local schema = {
  description = 'Get the most recent text selection (even if not in the active editor)',
  inputSchema = {
    type = 'object',
    additionalProperties = false,
    ['$schema'] = 'http://json-schema.org/draft-07/schema#',
  },
}

---Handles the getLatestSelection tool invocation.
---@param params table Input parameters (unused for this tool)
---@return table content MCP-compliant response with content array
local function handler(params)
  local state = require 'claude-inline.state'
  local selection = state.selected_text

  if not selection or selection == '' then
    return {
      content = {
        {
          type = 'text',
          text = vim.json.encode {
            success = false,
            message = 'No selection available',
          },
        },
      },
    }
  end

  local bufnr = state.main_bufnr
  local file_path = bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ''

  local selection_data = {
    success = true,
    text = selection,
    filePath = file_path,
    fileUrl = file_path ~= '' and ('file://' .. file_path) or '',
    selection = {
      isEmpty = false,
    },
  }

  -- Add position info if available
  if state.selection_start and state.selection_end then
    selection_data.selection.start = {
      line = state.selection_start.line or 0,
      character = state.selection_start.character or 0,
    }
    selection_data.selection['end'] = {
      line = state.selection_end.line or 0,
      character = state.selection_end.character or 0,
    }
  end

  -- Add timestamp if available
  if state.selection_timestamp then
    selection_data.timestamp = state.selection_timestamp
  end

  return {
    content = {
      {
        type = 'text',
        text = vim.json.encode(selection_data),
      },
    },
  }
end

return {
  name = 'getLatestSelection',
  schema = schema,
  handler = handler,
}
