--- Shared UI state for claude-inline.nvim
--- All UI components import this module for state access

---@class MessageBlock
---@field id number Extmark ID
---@field role 'user'|'assistant'|'tool'|'error'
---@field folded boolean Whether currently collapsed

---@class ContentBlock
---@field type 'text'|'tool_use'|'tool_result'
---@field id string|nil Tool use ID (for tool_use/tool_result)
---@field name string|nil Tool name (for tool_use)
---@field start_line number 0-indexed line where block starts
---@field end_line number|nil 0-indexed line where block ends
---@field folded boolean Whether currently collapsed
---@field state 'running'|'success'|'error'|nil State for tool blocks
---@field input_json string|nil Accumulated JSON input for tool_use

---@class UIState
---@field sidebar_win number|nil
---@field sidebar_buf number|nil
---@field input_win number|nil
---@field input_buf number|nil
---@field loading_timer uv.uv_timer_t|nil
---@field spinner_index number
---@field config table|nil
---@field message_blocks MessageBlock[] Array of message blocks with extmark IDs
---@field current_message_open boolean Whether current message needs closing fold marker
---@field content_blocks table<string, ContentBlock> Active content blocks by ID
---@field task_stack string[] Stack of active Task IDs (for nesting)

local M = {
  sidebar_win = nil,
  sidebar_buf = nil,
  input_win = nil,
  input_buf = nil,
  loading_timer = nil,
  spinner_index = 1,
  config = nil,
  message_blocks = {},
  current_message_open = false,
  content_blocks = {},
  task_stack = {},
}

-- Namespace for message block extmarks
M.MESSAGE_NS = vim.api.nvim_create_namespace 'claude_inline_messages'

return M
