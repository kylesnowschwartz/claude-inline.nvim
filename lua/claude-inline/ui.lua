--- UI components for claude-inline.nvim
--- Sidebar, input prompt, and loading spinner
local M = {}

local uv = vim.uv or vim.loop

-- Namespace for message block extmarks
local MESSAGE_NS = vim.api.nvim_create_namespace("claude_inline_messages")

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
---@field current_tool_id string|nil Currently streaming tool_use block ID

M._state = {
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
  current_tool_id = nil,
}

-- Helper functions to reduce duplication

--- Execute a function with the sidebar buffer temporarily modifiable
---@param fn function Function to execute
---@return any Result from fn
local function with_modifiable(fn)
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end
  vim.api.nvim_set_option_value("modifiable", true, { buf = M._state.sidebar_buf })
  local ok, result = pcall(fn)
  vim.api.nvim_set_option_value("modifiable", false, { buf = M._state.sidebar_buf })
  if not ok then
    error(result)
  end
  return result
end

--- Scroll sidebar window to bottom if visible
local function scroll_to_bottom()
  if M.is_sidebar_open() then
    local line_count = vim.api.nvim_buf_line_count(M._state.sidebar_buf)
    vim.api.nvim_win_set_cursor(M._state.sidebar_win, { line_count, 0 })
  end
end

--- Foldexpr function for sidebar buffer
--- Returns fold level based on message headers, thinking sections, and tool blocks
---@return string Fold level expression
function M.foldexpr()
  local lnum = vim.v.lnum

  -- IMPORTANT: vim.fn.getline() may read from wrong buffer when foldexpr is evaluated
  -- Explicitly read from the sidebar buffer to ensure correct content
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return "="
  end

  local lines = vim.api.nvim_buf_get_lines(M._state.sidebar_buf, lnum - 1, lnum, false)
  local line = lines[1] or ""

  -- Message headers start level 1 folds
  -- >1 means "start a fold at level 1" - automatically closes previous level 1 fold
  if line:match("^%*%*You:%*%*") or line:match("^%*%*Claude:%*%*") then
    return ">1"
  end

  -- Tool use/result headers start level 2 folds (nested inside assistant)
  if line:match("^> %[tool:") or line:match("^> %[result:") then
    return ">2"
  end

  -- Lines with > prefix are inside nested sections (level 2)
  -- This covers thinking content, tool parameters, and tool results
  if line:match("^> ") then
    return "2"
  end

  -- Transition out of nested section: previous line was prefixed, this isn't
  local prev_lines = vim.api.nvim_buf_get_lines(M._state.sidebar_buf, lnum - 2, lnum - 1, false)
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
  local line = vim.fn.getline(foldstart)

  -- Extract role from header
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

--- Close input window and cleanup state
---@param win number Window handle to close
local function close_input(win)
  vim.api.nvim_win_close(win, true)
  M._state.input_win = nil
  M._state.input_buf = nil
  vim.cmd("stopinsert")
end

--- Create an extmark to track a message block boundary
---@param role 'user'|'assistant'
---@param start_line number 0-indexed line where message starts
---@return number extmark_id
local function create_message_extmark(role, start_line)
  local mark_id = vim.api.nvim_buf_set_extmark(M._state.sidebar_buf, MESSAGE_NS, start_line, 0, {
    right_gravity = false, -- Stays put when text inserted at this position
  })
  table.insert(M._state.message_blocks, { id = mark_id, role = role, folded = false })
  return mark_id
end

--- Setup UI module with configuration
---@param config table
function M.setup(config)
  M._state.config = config
end

--- Check if sidebar is open
---@return boolean
function M.is_sidebar_open()
  return M._state.sidebar_win ~= nil and vim.api.nvim_win_is_valid(M._state.sidebar_win)
end

--- Show the sidebar
function M.show_sidebar()
  -- Sidebar already visible, nothing to do
  if M.is_sidebar_open() then
    return
  end

  -- Save current window to restore focus after creating sidebar
  local original_win = vim.api.nvim_get_current_win()

  local config = M._state.config.ui.sidebar

  -- Create sidebar buffer if needed
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    M._state.sidebar_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = M._state.sidebar_buf })
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M._state.sidebar_buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = M._state.sidebar_buf })
    vim.api.nvim_buf_set_name(M._state.sidebar_buf, "Claude Chat")
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = M._state.sidebar_buf })

    -- Enable treesitter highlighting (doesn't auto-activate on scratch buffers)
    pcall(vim.treesitter.start, M._state.sidebar_buf, "markdown")
  end

  -- Calculate width
  local width = math.floor(vim.o.columns * config.width)

  -- Create split (this focuses the new window)
  local cmd = config.position == "left" and "topleft" or "botright"
  vim.cmd(cmd .. " vertical " .. width .. "split")

  M._state.sidebar_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M._state.sidebar_win, M._state.sidebar_buf)

  -- Window options
  vim.api.nvim_set_option_value("wrap", true, { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value("linebreak", true, { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value("number", false, { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = M._state.sidebar_win })
  -- Folding: use manual initially, switch to expr after content is added
  -- This prevents vim from caching foldlevel=0 for empty buffer lines
  vim.api.nvim_set_option_value("foldmethod", "manual", { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value(
    "foldexpr",
    "v:lua.require'claude-inline.ui'.foldexpr()",
    { win = M._state.sidebar_win }
  )
  vim.api.nvim_set_option_value(
    "foldtext",
    "v:lua.require'claude-inline.ui'.foldtext()",
    { win = M._state.sidebar_win }
  )
  vim.api.nvim_set_option_value("foldenable", true, { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value("foldlevel", 99, { win = M._state.sidebar_win }) -- Start open, collapse manually

  -- Setup autocmd to track window close
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(M._state.sidebar_win),
    once = true,
    callback = function()
      M._state.sidebar_win = nil
    end,
  })

  -- Restore focus to original window - sidebar is for display, not editing
  vim.api.nvim_set_current_win(original_win)
end

--- Hide the sidebar
function M.hide_sidebar()
  if M.is_sidebar_open() then
    vim.api.nvim_win_close(M._state.sidebar_win, true)
    M._state.sidebar_win = nil
  end
end

--- Toggle the sidebar
function M.toggle_sidebar()
  if M.is_sidebar_open() then
    M.hide_sidebar()
  else
    M.show_sidebar()
  end
end

--- Append a message to the conversation buffer
---@param role string 'user' or 'assistant'
---@param text string
function M.append_message(role, text)
  -- Close any open message before starting a new one
  M.close_current_message()

  -- Message header (foldexpr detects these for folding)
  local prefix = role == "user" and "**You:**" or "**Claude:**"
  local lines = vim.split(prefix .. "\n" .. text .. "\n\n", "\n", { plain = true })
  local start_line

  with_modifiable(function()
    local line_count = vim.api.nvim_buf_line_count(M._state.sidebar_buf)
    local last_line = vim.api.nvim_buf_get_lines(M._state.sidebar_buf, line_count - 1, line_count, false)[1]

    -- If buffer is empty (just one empty line), replace it
    if line_count == 1 and last_line == "" then
      start_line = 0
      vim.api.nvim_buf_set_lines(M._state.sidebar_buf, 0, 1, false, lines)
    else
      start_line = line_count -- 0-indexed: next line after current content
      vim.api.nvim_buf_set_lines(M._state.sidebar_buf, -1, -1, false, lines)
    end
  end)

  -- Force vim to evaluate foldexpr after buffer content changes
  -- NOTE: vim caches fold levels and doesn't always re-evaluate when content changes
  -- Toggle through manual mode to force re-evaluation, then use zx to update
  if M.is_sidebar_open() then
    vim.api.nvim_win_call(M._state.sidebar_win, function()
      if vim.wo.foldmethod == "expr" then
        vim.cmd("setlocal foldmethod=manual")
      end
      vim.cmd("setlocal foldmethod=expr")
      vim.cmd("silent! normal! zx")
    end)
  end

  -- Track that assistant message is still streaming
  M._state.current_message_open = (role == "assistant")

  create_message_extmark(role, start_line)

  -- Collapse previous messages (but not the new one)
  -- Schedule fold closing to ensure foldexpr has evaluated the new content
  if M.is_sidebar_open() and #M._state.message_blocks > 1 then
    -- Capture current block count at scheduling time
    local blocks_to_close = #M._state.message_blocks - 1
    vim.schedule(function()
      if not M.is_sidebar_open() then
        return
      end
      vim.api.nvim_win_call(M._state.sidebar_win, function()
        -- Close each previous message fold individually (not zM which changes foldlevel)
        for i = 1, blocks_to_close do
          local block = M._state.message_blocks[i]
          if block then
            local mark = vim.api.nvim_buf_get_extmark_by_id(M._state.sidebar_buf, MESSAGE_NS, block.id, {})
            if mark and #mark > 0 then
              local line = mark[1] + 1
              local line_content = vim.fn.getline(line)
              local foldlevel_before = vim.fn.foldlevel(line)
              local closed_before = vim.fn.foldclosed(line)
              vim.api.nvim_win_set_cursor(M._state.sidebar_win, { line, 0 })
              vim.cmd("silent! normal! zc")
              local closed_after = vim.fn.foldclosed(line)
              -- Debug output
              if M._state.config and M._state.config.debug then
                local debug = require("claude-inline.debug")
                debug.log(
                  "FOLD",
                  string.format(
                    "block %d (%s) line %d [%s]: foldlevel=%d, closed %d->%d",
                    i,
                    block.role,
                    line,
                    line_content:sub(1, 20),
                    foldlevel_before,
                    closed_before,
                    closed_after
                  )
                )
              end
              block.folded = true
            end
          end
        end
      end)
    end)
  end

  scroll_to_bottom()
end

--- Update the last assistant message (for streaming)
---@param text string
function M.update_last_message(text)
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end

  -- Get last assistant block via extmarks
  local last_block = M._state.message_blocks[#M._state.message_blocks]
  if not last_block or last_block.role ~= "assistant" then
    return
  end

  local mark = vim.api.nvim_buf_get_extmark_by_id(M._state.sidebar_buf, MESSAGE_NS, last_block.id, {})
  if not mark or #mark == 0 then
    return
  end

  -- Content starts after header line (mark[1] is 0-indexed row)
  local start_line = mark[1] + 1

  local new_lines = vim.split(text .. "\n", "\n", { plain = true })

  with_modifiable(function()
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, start_line, -1, false, new_lines)
  end)

  scroll_to_bottom()
end

--- Mark the current message as complete
--- Called when streaming completes or before starting a new message
function M.close_current_message()
  -- Just mark the message as complete (foldexpr handles fold boundaries)
  M._state.current_message_open = false
end

-- ============================================================================
-- Tool Use Component
-- ============================================================================

--- Show a tool use block in the sidebar
--- Called when content_block_start with type="tool_use" is received
---@param tool_id string The unique tool use ID
---@param tool_name string The tool name (e.g., "read_file", "bash")
---@param input table|nil Initial input parameters (may be empty during streaming)
function M.show_tool_use(tool_id, tool_name, input)
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end

  -- Store the content block state
  local line_count = vim.api.nvim_buf_line_count(M._state.sidebar_buf)
  M._state.content_blocks[tool_id] = {
    type = "tool_use",
    id = tool_id,
    name = tool_name,
    start_line = line_count, -- 0-indexed
    end_line = nil,
    folded = false,
    state = "running",
    input_json = "",
  }
  M._state.current_tool_id = tool_id

  -- Render the tool header and initial content
  local header = string.format("> [tool: %s] running...", tool_name)
  local lines = { header, "> +--" }

  -- If we have initial input, format it
  if input and next(input) then
    for key, value in pairs(input) do
      local value_str = type(value) == "string" and value or vim.json.encode(value)
      -- Truncate long values
      if #value_str > 60 then
        value_str = value_str:sub(1, 57) .. "..."
      end
      table.insert(lines, string.format("> |   %s: %s", key, value_str))
    end
  end

  table.insert(lines, "> +--")

  with_modifiable(function()
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, -1, -1, false, lines)
  end)

  scroll_to_bottom()
end

--- Update tool input as JSON streams in
--- Called on content_block_delta with type="input_json_delta"
---@param tool_id string The tool use ID
---@param partial_json string Partial JSON fragment to accumulate
function M.update_tool_input(tool_id, partial_json)
  local block = M._state.content_blocks[tool_id]
  if not block then
    return
  end

  -- Accumulate the JSON string
  block.input_json = (block.input_json or "") .. partial_json

  -- Try to parse and display what we have so far
  -- This is best-effort - partial JSON may not parse
  local ok, input = pcall(vim.json.decode, block.input_json)
  if ok and input and type(input) == "table" then
    -- Re-render the tool block with current input
    local header = string.format("> [tool: %s] running...", block.name)
    local lines = { header, "> +--" }

    for key, value in pairs(input) do
      local value_str = type(value) == "string" and value or vim.json.encode(value)
      if #value_str > 60 then
        value_str = value_str:sub(1, 57) .. "..."
      end
      table.insert(lines, string.format("> |   %s: %s", key, value_str))
    end

    table.insert(lines, "> +--")

    with_modifiable(function()
      vim.api.nvim_buf_set_lines(M._state.sidebar_buf, block.start_line, -1, false, lines)
    end)

    scroll_to_bottom()
  end
end

--- Mark a tool use as complete
--- Called on content_block_stop for tool_use blocks
---@param tool_id string The tool use ID
---@param state? 'success'|'error' Final state (default: 'success')
function M.complete_tool(tool_id, state)
  local block = M._state.content_blocks[tool_id]
  if not block then
    return
  end

  block.state = state or "success"
  block.end_line = vim.api.nvim_buf_line_count(M._state.sidebar_buf) - 1

  -- Parse final input JSON
  local input = {}
  if block.input_json and block.input_json ~= "" then
    local ok, parsed = pcall(vim.json.decode, block.input_json)
    if ok then
      input = parsed
    end
  end

  -- Re-render with final state
  local status = block.state == "success" and "done" or "error"
  local header = string.format("> [tool: %s] %s", block.name, status)
  local lines = { header, "> +--" }

  if input and next(input) then
    for key, value in pairs(input) do
      local value_str = type(value) == "string" and value or vim.json.encode(value)
      if #value_str > 60 then
        value_str = value_str:sub(1, 57) .. "..."
      end
      table.insert(lines, string.format("> |   %s: %s", key, value_str))
    end
  end

  table.insert(lines, "> +--")
  table.insert(lines, "") -- Blank line after tool block

  with_modifiable(function()
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, block.start_line, -1, false, lines)
  end)

  -- Clear current tool tracking
  if M._state.current_tool_id == tool_id then
    M._state.current_tool_id = nil
  end

  scroll_to_bottom()
end

--- Collapse a tool use block
---@param tool_id string The tool use ID
function M.collapse_tool(tool_id)
  local block = M._state.content_blocks[tool_id]
  if not block or block.folded then
    return
  end

  if M.is_sidebar_open() then
    vim.schedule(function()
      pcall(function()
        -- Move to tool header line and close fold
        vim.api.nvim_win_set_cursor(M._state.sidebar_win, { block.start_line + 1, 0 })
        vim.api.nvim_win_call(M._state.sidebar_win, function()
          vim.cmd("normal! zc")
        end)
        scroll_to_bottom()
      end)
    end)
  end

  block.folded = true
end

-- ============================================================================
-- Tool Result Component
-- ============================================================================

--- Show a tool result block in the sidebar
--- Called when processing tool_result content blocks from user messages
---@param tool_use_id string The ID of the tool_use this result is for
---@param content string The result content
---@param is_error boolean|nil Whether this is an error result
---@param metadata table|nil Optional metadata (durationMs, numFiles, exitCode, truncated)
function M.show_tool_result(tool_use_id, content, is_error, metadata)
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end

  -- Find the corresponding tool_use block for the name
  local tool_block = M._state.content_blocks[tool_use_id]
  local tool_name = tool_block and tool_block.name or "unknown"

  -- Store the content block state
  local line_count = vim.api.nvim_buf_line_count(M._state.sidebar_buf)
  local result_id = "result_" .. tool_use_id
  M._state.content_blocks[result_id] = {
    type = "tool_result",
    id = result_id,
    name = tool_name,
    start_line = line_count, -- 0-indexed
    end_line = nil,
    folded = false,
    state = is_error and "error" or "success",
  }

  -- Format the result header with metadata
  local header_parts = {}
  if metadata then
    -- For file operations, show file count
    if metadata.numFiles then
      table.insert(header_parts, string.format("%d files", metadata.numFiles))
    end
    -- For bash commands, show exit code if non-zero
    if metadata.exitCode and metadata.exitCode ~= 0 then
      table.insert(header_parts, string.format("exit %d", metadata.exitCode))
    end
    -- Show duration
    if metadata.durationMs then
      if metadata.durationMs >= 1000 then
        table.insert(header_parts, string.format("%.1fs", metadata.durationMs / 1000))
      else
        table.insert(header_parts, string.format("%dms", metadata.durationMs))
      end
    end
    -- Note if truncated
    if metadata.truncated then
      table.insert(header_parts, "truncated")
    end
  end

  local status = is_error and "error" or "success"
  local header
  if #header_parts > 0 then
    header = string.format("> [result: %s] %s (%s)", tool_name, status, table.concat(header_parts, ", "))
  else
    header = string.format("> [result: %s] %s", tool_name, status)
  end
  local lines = { header, "> +--" }

  -- Summarize the content
  local content_lines = vim.split(content or "", "\n", { plain = true })
  local line_count_display = #content_lines

  if line_count_display > 5 then
    -- Show summary for long results
    table.insert(lines, string.format("> |   (%d lines)", line_count_display))
    -- Show first 3 lines as preview
    for i = 1, math.min(3, #content_lines) do
      local preview_line = content_lines[i]:sub(1, 55)
      if #content_lines[i] > 55 then
        preview_line = preview_line .. "..."
      end
      table.insert(lines, "> |   " .. preview_line)
    end
    if #content_lines > 3 then
      table.insert(lines, "> |   ...")
    end
  else
    -- Show full content for short results
    for _, line in ipairs(content_lines) do
      local display_line = line:sub(1, 60)
      if #line > 60 then
        display_line = display_line .. "..."
      end
      table.insert(lines, "> |   " .. display_line)
    end
  end

  table.insert(lines, "> +--")
  table.insert(lines, "") -- Blank line after result block

  with_modifiable(function()
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, -1, -1, false, lines)
  end)

  M._state.content_blocks[result_id].end_line = vim.api.nvim_buf_line_count(M._state.sidebar_buf) - 1

  scroll_to_bottom()
end

--- Collapse a tool result block
---@param tool_use_id string The tool use ID (result ID will be derived)
function M.collapse_tool_result(tool_use_id)
  local result_id = "result_" .. tool_use_id
  local block = M._state.content_blocks[result_id]
  if not block or block.folded then
    return
  end

  if M.is_sidebar_open() then
    vim.schedule(function()
      pcall(function()
        vim.api.nvim_win_set_cursor(M._state.sidebar_win, { block.start_line + 1, 0 })
        vim.api.nvim_win_call(M._state.sidebar_win, function()
          vim.cmd("normal! zc")
        end)
        scroll_to_bottom()
      end)
    end)
  end

  block.folded = true
end

--- Clear the conversation buffer
function M.clear()
  -- Clear extmarks and reset block tracking
  if M._state.sidebar_buf and vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    vim.api.nvim_buf_clear_namespace(M._state.sidebar_buf, MESSAGE_NS, 0, -1)
  end
  M._state.message_blocks = {}

  with_modifiable(function()
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, 0, -1, false, {})
  end)

  M._state.current_message_open = false

  -- Reset content block state
  M._state.content_blocks = {}
  M._state.current_tool_id = nil
end

--- Get the message block at cursor position
---@return MessageBlock|nil
function M.get_block_at_cursor()
  if not M.is_sidebar_open() then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(M._state.sidebar_win)
  local cursor_line = cursor[1] - 1 -- Convert to 0-indexed
  local line_count = vim.api.nvim_buf_line_count(M._state.sidebar_buf)

  -- With point extmarks, block end = next block's start (or buffer end)
  for i, block in ipairs(M._state.message_blocks) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(M._state.sidebar_buf, MESSAGE_NS, block.id, {})
    if mark and #mark >= 1 then
      local start_row = mark[1]
      local end_row

      -- End is either next block's start or buffer end
      if i < #M._state.message_blocks then
        local next_mark =
          vim.api.nvim_buf_get_extmark_by_id(M._state.sidebar_buf, MESSAGE_NS, M._state.message_blocks[i + 1].id, {})
        end_row = next_mark and next_mark[1] - 1 or line_count - 1
      else
        end_row = line_count - 1
      end

      if cursor_line >= start_row and cursor_line <= end_row then
        return block
      end
    end
  end
  return nil
end

--- Get all message blocks in the conversation
---@return MessageBlock[]
function M.get_all_blocks()
  return vim.deepcopy(M._state.message_blocks)
end

--- Show input prompt window
---@param callback fun(input: string|nil)
function M.show_input(callback)
  -- Close existing input if open
  if M._state.input_win and vim.api.nvim_win_is_valid(M._state.input_win) then
    vim.api.nvim_win_close(M._state.input_win, true)
  end

  local config = M._state.config.ui.input

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  -- Calculate position (center of editor)
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight
  local width = config.width
  local height = config.height
  local row = math.floor((editor_height - height) / 2)
  local col = math.floor((editor_width - width) / 2)

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = config.border,
    title = " Send to Claude ",
    title_pos = "center",
    footer = " <CR>: Send | <Esc>: Cancel ",
    footer_pos = "center",
  })

  M._state.input_win = win
  M._state.input_buf = buf

  vim.cmd("startinsert")

  -- Keymaps
  local opts = { buffer = buf, nowait = true, noremap = true, silent = true }

  -- Accept input with Enter
  vim.keymap.set("i", "<CR>", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(lines, "\n")
    input = vim.trim(input)

    close_input(win)

    if callback and input ~= "" then
      callback(input)
    elseif callback then
      callback(nil)
    end
  end, opts)

  -- Cancel with Escape
  vim.keymap.set({ "i", "n" }, "<Esc>", function()
    close_input(win)
    if callback then
      callback(nil)
    end
  end, opts)
end

--- Show loading indicator in sidebar
function M.show_loading()
  if M._state.loading_timer then
    return
  end

  local config = M._state.config.ui.loading

  -- Add "Claude:" marker first
  M.append_message("assistant", "")

  M._state.spinner_index = 1
  M._state.loading_timer = uv.new_timer()

  M._state.loading_timer:start(
    0,
    config.interval,
    vim.schedule_wrap(function()
      if not M._state.loading_timer then
        return
      end

      local spinner = config.spinner[M._state.spinner_index]
      local text = spinner .. " " .. config.text
      M.update_last_message(text)

      M._state.spinner_index = M._state.spinner_index % #config.spinner + 1
    end)
  )
end

--- Hide loading indicator
function M.hide_loading()
  if M._state.loading_timer then
    M._state.loading_timer:stop()
    M._state.loading_timer:close()
    M._state.loading_timer = nil
  end
end

--- Cleanup all UI elements
function M.cleanup()
  M.hide_loading()

  if M._state.input_win and vim.api.nvim_win_is_valid(M._state.input_win) then
    vim.api.nvim_win_close(M._state.input_win, true)
  end
  M._state.input_win = nil
  M._state.input_buf = nil
  M._state.message_blocks = {}
  M._state.current_message_open = false
  M._state.content_blocks = {}
  M._state.current_tool_id = nil
end

--- Collapse all message blocks in the sidebar
function M.fold_all()
  if not M.is_sidebar_open() then
    return
  end

  vim.api.nvim_win_call(M._state.sidebar_win, function()
    vim.cmd("silent! normal! zM")
  end)

  for _, block in ipairs(M._state.message_blocks) do
    block.folded = true
  end
end

--- Expand all message blocks in the sidebar
function M.unfold_all()
  if not M.is_sidebar_open() then
    return
  end

  vim.api.nvim_win_call(M._state.sidebar_win, function()
    vim.cmd("silent! %foldopen!")
  end)

  for _, block in ipairs(M._state.message_blocks) do
    block.folded = false
  end
end

return M
