--- UI components for claude-inline.nvim
--- Sidebar, input prompt, and loading spinner
local M = {}

local uv = vim.uv or vim.loop

-- Namespace for message block extmarks
local MESSAGE_NS = vim.api.nvim_create_namespace 'claude_inline_messages'

---@class MessageBlock
---@field id number Extmark ID
---@field role 'user'|'assistant'

---@class UIState
---@field sidebar_win number|nil
---@field sidebar_buf number|nil
---@field input_win number|nil
---@field input_buf number|nil
---@field loading_timer uv.uv_timer_t|nil
---@field spinner_index number
---@field config table|nil
---@field thinking_start_line number|nil Line where thinking section starts
---@field thinking_active boolean Whether currently streaming thinking
---@field response_start_line number|nil Line where response text starts (after thinking)
---@field message_blocks MessageBlock[] Array of message blocks with extmark IDs

M._state = {
  sidebar_win = nil,
  sidebar_buf = nil,
  input_win = nil,
  input_buf = nil,
  loading_timer = nil,
  spinner_index = 1,
  config = nil,
  thinking_start_line = nil,
  thinking_active = false,
  response_start_line = nil,
  message_blocks = {},
}

-- Helper functions to reduce duplication

--- Execute a function with the sidebar buffer temporarily modifiable
---@param fn function Function to execute
---@return any Result from fn
local function with_modifiable(fn)
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end
  vim.api.nvim_set_option_value('modifiable', true, { buf = M._state.sidebar_buf })
  local ok, result = pcall(fn)
  vim.api.nvim_set_option_value('modifiable', false, { buf = M._state.sidebar_buf })
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

--- Close input window and cleanup state
---@param win number Window handle to close
local function close_input(win)
  vim.api.nvim_win_close(win, true)
  M._state.input_win = nil
  M._state.input_buf = nil
  vim.cmd 'stopinsert'
end

--- Create an extmark to track a message block boundary
---@param role 'user'|'assistant'
---@param start_line number 0-indexed line where message starts
---@return number extmark_id
local function create_message_extmark(role, start_line)
  local mark_id = vim.api.nvim_buf_set_extmark(M._state.sidebar_buf, MESSAGE_NS, start_line, 0, {
    right_gravity = false, -- Stays put when text inserted at this position
  })
  table.insert(M._state.message_blocks, { id = mark_id, role = role })
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
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = M._state.sidebar_buf })
    vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = M._state.sidebar_buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = M._state.sidebar_buf })
    vim.api.nvim_buf_set_name(M._state.sidebar_buf, 'Claude Chat')
    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = M._state.sidebar_buf })

    -- Enable treesitter highlighting (doesn't auto-activate on scratch buffers)
    pcall(vim.treesitter.start, M._state.sidebar_buf, 'markdown')
  end

  -- Calculate width
  local width = math.floor(vim.o.columns * config.width)

  -- Create split (this focuses the new window)
  local cmd = config.position == 'left' and 'topleft' or 'botright'
  vim.cmd(cmd .. ' vertical ' .. width .. 'split')

  M._state.sidebar_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M._state.sidebar_win, M._state.sidebar_buf)

  -- Window options
  vim.api.nvim_set_option_value('wrap', true, { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value('linebreak', true, { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value('number', false, { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value('relativenumber', false, { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { win = M._state.sidebar_win })
  -- Folding for collapsible thinking sections
  vim.api.nvim_set_option_value('foldmethod', 'marker', { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value('foldenable', true, { win = M._state.sidebar_win })
  vim.api.nvim_set_option_value('foldlevel', 99, { win = M._state.sidebar_win }) -- Start open, collapse manually

  -- Setup autocmd to track window close
  vim.api.nvim_create_autocmd('WinClosed', {
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
  local prefix = role == 'user' and '**You:**' or '**Claude:**'
  local lines = vim.split(prefix .. '\n' .. text .. '\n\n', '\n', { plain = true })
  local start_line

  with_modifiable(function()
    local line_count = vim.api.nvim_buf_line_count(M._state.sidebar_buf)
    local last_line = vim.api.nvim_buf_get_lines(M._state.sidebar_buf, line_count - 1, line_count, false)[1]

    -- If buffer is empty (just one empty line), replace it
    if line_count == 1 and last_line == '' then
      start_line = 0
      vim.api.nvim_buf_set_lines(M._state.sidebar_buf, 0, 1, false, lines)
    else
      start_line = line_count -- 0-indexed: next line after current content
      vim.api.nvim_buf_set_lines(M._state.sidebar_buf, -1, -1, false, lines)
    end
  end)

  create_message_extmark(role, start_line)
  scroll_to_bottom()
end

--- Update the last assistant message (for streaming)
---@param text string
function M.update_last_message(text)
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end

  local start_line

  -- If we have a response start line (after thinking section), use that
  if M._state.response_start_line then
    start_line = M._state.response_start_line
  else
    -- Get last assistant block via extmarks
    local last_block = M._state.message_blocks[#M._state.message_blocks]
    if not last_block or last_block.role ~= 'assistant' then
      return
    end

    local mark = vim.api.nvim_buf_get_extmark_by_id(M._state.sidebar_buf, MESSAGE_NS, last_block.id, {})
    if not mark or #mark == 0 then
      return
    end

    -- Content starts after header line (mark[1] is 0-indexed row)
    start_line = mark[1] + 1
  end

  local new_lines = vim.split(text .. '\n', '\n', { plain = true })

  with_modifiable(function()
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, start_line, -1, false, new_lines)
  end)

  scroll_to_bottom()
end

--- Start a thinking section in the sidebar
--- Note: Called after show_loading, which already added **Claude:** header
function M.show_thinking()
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end

  M._state.thinking_active = true

  -- Insert thinking header with fold marker (replaces the loading spinner)
  local header = '> *Thinking...* {{{'

  -- Find last assistant block via extmarks
  local last_block = M._state.message_blocks[#M._state.message_blocks]
  if not last_block or last_block.role ~= 'assistant' then
    return
  end

  local mark = vim.api.nvim_buf_get_extmark_by_id(M._state.sidebar_buf, MESSAGE_NS, last_block.id, {})
  if not mark or #mark == 0 then
    return
  end

  -- mark[1] is 0-indexed row where **Claude:** header is
  local header_row = mark[1]

  with_modifiable(function()
    -- Replace everything after Claude: header with thinking header
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, header_row + 1, -1, false, { header })
  end)

  -- Thinking content starts after the thinking header line
  M._state.thinking_start_line = header_row + 2
end

--- Update thinking content (streaming)
---@param text string Full thinking text so far
function M.update_thinking(text)
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end

  if not M._state.thinking_start_line then
    return
  end

  -- Format thinking lines with > prefix
  local thinking_lines = vim.split(text, '\n', { plain = true })
  local formatted = {}
  for _, line in ipairs(thinking_lines) do
    table.insert(formatted, '> ' .. line)
  end

  -- Replace from thinking start line onward
  -- Keep the header line, replace content after it
  local start_line = M._state.thinking_start_line
  with_modifiable(function()
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, start_line, -1, false, formatted)
  end)

  scroll_to_bottom()
end

--- Collapse thinking section and prepare for response
function M.collapse_thinking()
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end

  if not M._state.thinking_start_line or not M._state.thinking_active then
    return
  end

  M._state.thinking_active = false

  with_modifiable(function()
    -- Count thinking lines for summary
    local line_count = vim.api.nvim_buf_line_count(M._state.sidebar_buf)
    local thinking_line_count = line_count - M._state.thinking_start_line

    -- Update header to show line count
    local header_line = M._state.thinking_start_line - 1 -- 0-indexed
    local header = string.format('> *Thinking (%d lines)* {{{', thinking_line_count)
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, header_line, header_line + 1, false, { header })

    -- Add closing fold marker and blank line for response
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, -1, -1, false, { '> }}}', '' })

    -- Track where response text should start
    M._state.response_start_line = vim.api.nvim_buf_line_count(M._state.sidebar_buf)
  end)

  -- Close the fold if sidebar window is valid
  if M.is_sidebar_open() then
    vim.schedule(function()
      -- Move cursor to thinking header and close fold
      local header_lnum = M._state.thinking_start_line
      pcall(function()
        vim.api.nvim_win_set_cursor(M._state.sidebar_win, { header_lnum, 0 })
        vim.api.nvim_win_call(M._state.sidebar_win, function()
          vim.cmd 'normal! zc'
        end)
        scroll_to_bottom()
      end)
    end)
  end

  M._state.thinking_start_line = nil
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

  -- Reset thinking state
  M._state.thinking_start_line = nil
  M._state.thinking_active = false
  M._state.response_start_line = nil
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
        local next_mark = vim.api.nvim_buf_get_extmark_by_id(M._state.sidebar_buf, MESSAGE_NS, M._state.message_blocks[i + 1].id, {})
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
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })

  -- Calculate position (center of editor)
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight
  local width = config.width
  local height = config.height
  local row = math.floor((editor_height - height) / 2)
  local col = math.floor((editor_width - width) / 2)

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = config.border,
    title = ' Send to Claude ',
    title_pos = 'center',
    footer = ' <CR>: Send | <Esc>: Cancel ',
    footer_pos = 'center',
  })

  M._state.input_win = win
  M._state.input_buf = buf

  vim.cmd 'startinsert'

  -- Keymaps
  local opts = { buffer = buf, nowait = true, noremap = true, silent = true }

  -- Accept input with Enter
  vim.keymap.set('i', '<CR>', function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(lines, '\n')
    input = vim.trim(input)

    close_input(win)

    if callback and input ~= '' then
      callback(input)
    elseif callback then
      callback(nil)
    end
  end, opts)

  -- Cancel with Escape
  vim.keymap.set({ 'i', 'n' }, '<Esc>', function()
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
  M.append_message('assistant', '')

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
      local text = spinner .. ' ' .. config.text
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
  M._state.thinking_start_line = nil
  M._state.thinking_active = false
  M._state.response_start_line = nil
  M._state.message_blocks = {}
end

return M
