--- Folding system for claude-inline.nvim
--- Manages fold expressions and text for sidebar buffer

local state = require("claude-inline.ui.state")
local buffer = require("claude-inline.ui.buffer")

local M = {}

--- Foldexpr function for sidebar buffer
--- Returns fold level based on message headers, thinking sections, and tool blocks
---@return string Fold level expression
function M.foldexpr()
  local lnum = vim.v.lnum

  -- IMPORTANT: vim.fn.getline() may read from wrong buffer when foldexpr is evaluated
  -- Explicitly read from the sidebar buffer to ensure correct content
  if not buffer.is_valid() then
    return "="
  end

  local lines = vim.api.nvim_buf_get_lines(state.sidebar_buf, lnum - 1, lnum, false)
  local line = lines[1] or ""

  -- Message headers start level 1 folds
  -- >1 means "start a fold at level 1" - automatically closes previous level 1 fold
  if line:match("^%*%*You:%*%*") or line:match("^%*%*Claude:%*%*") then
    return ">1"
  end

  -- Task header starts level 2 fold: [Task xxx: description]
  -- Match: starts with [Task, has a colon after the ID (distinguishes from completion line)
  if line:match("^%[Task [^%]]+:") then
    return ">2"
  end

  -- Task children (indented with 2 spaces) stay at level 2
  if line:match("^  ") then
    return "2"
  end

  -- Task completion line: [Task xxx] ✓ (no colon, has ] followed by space)
  -- Stays at level 2, fold ends at next blank or non-indented line
  if line:match("^%[Task [^:]+%] ") then
    return "2"
  end

  -- Tools group header starts level 2 fold (groups all tools under one fold)
  if line:match("^> %[tools:") then
    return ">2"
  end

  -- Individual tool entries (tree-style) start level 3 folds (nested inside tools group)
  -- Matches: >   ├─ [tool] or >   └─ [tool]
  if line:match("^>   [├└]") then
    return ">3"
  end

  -- Thinking section header starts level 2 fold
  if line:match("^> %[thinking%]") then
    return ">2"
  end

  -- Legacy: old-style tool use/result headers start level 2 folds
  if line:match("^> %[tool:") or line:match("^> %[result:") then
    return ">2"
  end

  -- Tool content lines (tree connectors) stay at level 3
  -- Matches: >   │ (content) or >      (content after └)
  if line:match("^>   │") or line:match("^>      ") then
    return "3"
  end

  -- Lines with > prefix are inside nested sections (level 2)
  -- This covers thinking content and other prefixed content
  if line:match("^> ") then
    return "2"
  end

  -- Transition out of nested section: previous line was prefixed, this isn't
  local prev_lines = vim.api.nvim_buf_get_lines(state.sidebar_buf, lnum - 2, lnum - 1, false)
  local prev = prev_lines[1] or ""
  if prev:match("^> ") and not line:match("^> ") and line ~= "" then
    return "1" -- Back to level 1 (still in assistant message)
  end

  return "=" -- Inherit from previous line
end

--- Foldtext function for sidebar buffer
--- Shows role + truncated content preview
---@return string Fold display text
function M.foldtext()
  local foldstart = vim.v.foldstart
  local foldend = vim.v.foldend
  local line = vim.fn.getline(foldstart)

  -- Task header: show line count
  if line:match("^%[Task") then
    local line_count = foldend - foldstart
    return string.format("%s  (%d lines)", line, line_count)
  end

  -- Thinking section: show line count
  if line:match("^> %[thinking%]") then
    local line_count = foldend - foldstart
    return string.format("> [thinking]  (%d lines)", line_count)
  end

  -- Extract role from message header
  local role = line:match("^%*%*(.-):%*%*")
  if not role then
    return line -- Fallback
  end

  -- Get first content line for preview
  local content_line = vim.fn.getline(foldstart + 1)
  if content_line and content_line ~= "" then
    -- Truncate to 60 chars
    local preview = content_line:sub(1, 60)
    if #content_line > 60 then
      preview = preview .. "..."
    end
    return string.format("**%s:** %s", role, preview)
  end

  return line
end

--- Force vim to re-evaluate foldexpr after buffer content changes
--- NOTE: vim caches fold levels and doesn't always re-evaluate when content changes
--- Toggle through manual mode to force re-evaluation, then use zx to update
function M.refresh()
  if not buffer.is_sidebar_open() then
    return
  end
  vim.api.nvim_win_call(state.sidebar_win, function()
    if vim.wo.foldmethod == "expr" then
      vim.cmd("setlocal foldmethod=manual")
    end
    vim.cmd("setlocal foldmethod=expr")
    vim.cmd("silent! normal! zx")
  end)
end

--- Collapse all folds in sidebar
function M.fold_all()
  if not buffer.is_sidebar_open() then
    return
  end
  vim.api.nvim_win_call(state.sidebar_win, function()
    vim.cmd("silent! normal! zM")
  end)
end

--- Expand all folds in sidebar
function M.unfold_all()
  if not buffer.is_sidebar_open() then
    return
  end
  vim.api.nvim_win_call(state.sidebar_win, function()
    vim.cmd("silent! %foldopen!")
  end)
end

return M
