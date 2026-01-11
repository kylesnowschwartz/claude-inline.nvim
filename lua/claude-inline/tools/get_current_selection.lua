--- Tool implementation for getting the current selection.
--- Returns the current visual selection in the editor.

local schema = {
  description = 'Get the current text selection in the editor',
  inputSchema = {
    type = 'object',
    additionalProperties = false,
    ['$schema'] = 'http://json-schema.org/draft-07/schema#',
  },
}

---Helper function to safely encode data as JSON with error handling.
---@param data table The data to encode as JSON
---@param error_context string A description of what failed for error messages
---@return string The JSON-encoded string
local function safe_json_encode(data, error_context)
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    error {
      code = -32000,
      message = 'Internal server error',
      data = 'Failed to encode ' .. error_context .. ': ' .. tostring(encoded),
    }
  end
  return encoded
end

---Handles the getCurrentSelection tool invocation.
---@param params table Input parameters (unused for this tool)
---@return table response MCP-compliant response with selection data.
local function handler(params)
  local state = require 'claude-inline.state'
  local selection = state.selected_text
  local bufnr = state.main_bufnr

  if not selection or selection == '' then
    -- Check if there's an active editor/buffer
    local current_buf = vim.api.nvim_get_current_buf()
    local buf_name = vim.api.nvim_buf_get_name(current_buf)

    if not buf_name or buf_name == '' then
      -- No active editor case
      local no_editor_response = {
        success = false,
        message = 'No active editor found',
      }

      return {
        content = {
          {
            type = 'text',
            text = safe_json_encode(no_editor_response, 'no editor response'),
          },
        },
      }
    end

    -- Valid buffer but no selection
    local empty_selection = {
      success = true,
      text = '',
      filePath = buf_name,
      fileUrl = 'file://' .. buf_name,
      selection = {
        start = { line = 0, character = 0 },
        ['end'] = { line = 0, character = 0 },
        isEmpty = true,
      },
    }

    return {
      content = {
        {
          type = 'text',
          text = safe_json_encode(empty_selection, 'empty selection'),
        },
      },
    }
  end

  -- We have a selection
  local file_path = bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or vim.api.nvim_buf_get_name(0)

  local selection_data = {
    success = true,
    text = selection,
    filePath = file_path,
    fileUrl = 'file://' .. file_path,
    selection = {
      isEmpty = false,
    },
  }

  -- Add position info if available from state
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

  return {
    content = {
      {
        type = 'text',
        text = safe_json_encode(selection_data, 'selection'),
      },
    },
  }
end

return {
  name = 'getCurrentSelection',
  schema = schema,
  handler = handler,
}
