---@mod claude-inline.selection Visual selection handling
---@brief [[
--- Captures visual mode selections with proper mode handling.
--- Based on patterns from claudecode.nvim and claude-inline.nvim reference implementations.
---@brief ]]

local M = {}

---@class Selection
---@field text string Selected text
---@field filepath string Buffer file path (empty string if scratch)
---@field filetype string Buffer filetype
---@field start_line number Start line (1-indexed)
---@field end_line number End line (1-indexed)
---@field mode string Visual mode ('v', 'V', or '\22' for block)

--- Get character-wise selection (handles partial lines)
---@param bufnr number
---@param start_line number 1-indexed
---@param start_col number 0-indexed
---@param end_line number 1-indexed
---@param end_col number 0-indexed
---@return string[] lines
local function get_char_selection(bufnr, start_line, start_col, end_line, end_col)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  if #lines == 0 then
    return {}
  end

  if #lines == 1 then
    -- Single line: extract substring
    local line = lines[1]
    local byte_start = vim.fn.byteidx(line, start_col)
    local byte_end = vim.fn.byteidx(line, end_col + 1)
    if byte_start == -1 then
      byte_start = 0
    end
    if byte_end == -1 then
      byte_end = #line
    end
    lines[1] = string.sub(line, byte_start + 1, byte_end)
  else
    -- Multi-line: trim first and last
    local first = lines[1]
    local byte_start = vim.fn.byteidx(first, start_col)
    if byte_start == -1 then
      byte_start = 0
    end
    lines[1] = string.sub(first, byte_start + 1)

    local last = lines[#lines]
    local byte_end = vim.fn.byteidx(last, end_col + 1)
    if byte_end == -1 then
      byte_end = #last
    end
    lines[#lines] = string.sub(last, 1, byte_end)
  end

  return lines
end

--- Get block-wise selection (rectangular)
---@param bufnr number
---@param start_line number 1-indexed
---@param start_col number 0-indexed
---@param end_line number 1-indexed
---@param end_col number 0-indexed
---@return string[] lines
local function get_block_selection(bufnr, start_line, start_col, end_line, end_col)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local result = {}

  -- Ensure start_col <= end_col
  if start_col > end_col then
    start_col, end_col = end_col, start_col
  end

  for _, line in ipairs(lines) do
    local byte_start = vim.fn.byteidx(line, start_col)
    local byte_end = vim.fn.byteidx(line, end_col + 1)

    if byte_start == -1 then
      table.insert(result, "")
    else
      if byte_end == -1 then
        byte_end = #line
      end
      table.insert(result, string.sub(line, byte_start + 1, byte_end))
    end
  end

  return result
end

--- Capture the current visual selection
--- Must be called while still in visual mode, before <Esc>
---@return Selection|nil
function M.capture()
  local mode = vim.fn.visualmode()
  if mode == "" then
    -- Try current mode if visualmode() returns empty
    local current = vim.api.nvim_get_mode().mode
    if current == "v" or current == "V" or current == "\22" then
      mode = current
    else
      return nil
    end
  end

  -- Get selection bounds using 'v' mark (anchor) and cursor position
  local anchor = vim.fn.getpos("v")
  local cursor = vim.api.nvim_win_get_cursor(0)

  local p1 = { line = anchor[2], col = anchor[3] - 1 }
  local p2 = { line = cursor[1], col = cursor[2] }

  -- Normalize: p1 should be before p2
  local start_line, start_col, end_line, end_col
  if p1.line < p2.line or (p1.line == p2.line and p1.col <= p2.col) then
    start_line, start_col = p1.line, p1.col
    end_line, end_col = p2.line, p2.col
  else
    start_line, start_col = p2.line, p2.col
    end_line, end_col = p1.line, p1.col
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines

  if mode == "V" then
    -- Line-wise: full lines
    lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  elseif mode == "\22" then
    -- Block-wise
    lines = get_block_selection(bufnr, start_line, start_col, end_line, end_col)
  else
    -- Character-wise (default)
    lines = get_char_selection(bufnr, start_line, start_col, end_line, end_col)
  end

  if #lines == 0 then
    return nil
  end

  return {
    text = table.concat(lines, "\n"),
    filepath = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    start_line = start_line,
    end_line = end_line,
    mode = mode,
  }
end

--- Format selection as context for Claude prompt
---@param sel Selection
---@return string
function M.format_context(sel)
  local header
  if sel.filepath ~= "" then
    if sel.start_line == sel.end_line then
      header = string.format("%s:%d", sel.filepath, sel.start_line)
    else
      header = string.format("%s:%d-%d", sel.filepath, sel.start_line, sel.end_line)
    end
  else
    header = "[scratch buffer]"
  end

  local fence_lang = sel.filetype ~= "" and sel.filetype or ""
  return header .. "\n```" .. fence_lang .. "\n" .. sel.text .. "\n```\n\n"
end

return M
