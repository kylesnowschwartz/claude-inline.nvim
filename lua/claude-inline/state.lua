--- Shared state for Claude Code inline editing.
--- Tracks visual selections for MCP tools.
local M = {
  -- Selection tracking for MCP tools
  selected_text = '',
  main_bufnr = nil,
  selection_start = nil, -- { line = 0, character = 0 }
  selection_end = nil, -- { line = 0, character = 0 }
  selection_timestamp = nil, -- Unix timestamp when selection was made
}

---Update selection state
---@param text string The selected text
---@param bufnr number|nil The buffer number
---@param start_pos table|nil Start position { line, character }
---@param end_pos table|nil End position { line, character }
function M.set_selection(text, bufnr, start_pos, end_pos)
  M.selected_text = text or ''
  M.main_bufnr = bufnr
  M.selection_start = start_pos
  M.selection_end = end_pos
  M.selection_timestamp = os.time()
end

---Clear selection state
function M.clear_selection()
  M.selected_text = ''
  M.main_bufnr = nil
  M.selection_start = nil
  M.selection_end = nil
  M.selection_timestamp = nil
end

return M
