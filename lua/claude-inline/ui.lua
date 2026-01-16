--- UI components for claude-inline.nvim
--- Sidebar, input prompt, and loading spinner
local M = {}

local uv = vim.uv or vim.loop

---@class UIState
---@field sidebar_win number|nil
---@field sidebar_buf number|nil
---@field input_win number|nil
---@field input_buf number|nil
---@field loading_timer uv.uv_timer_t|nil
---@field spinner_index number
---@field config table|nil

M._state = {
  sidebar_win = nil,
  sidebar_buf = nil,
  input_win = nil,
  input_buf = nil,
  loading_timer = nil,
  spinner_index = 1,
  config = nil,
}

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
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end

  local prefix = role == 'user' and '**You:**' or '**Claude:**'
  local lines = vim.split(prefix .. '\n' .. text .. '\n\n', '\n', { plain = true })

  vim.api.nvim_set_option_value('modifiable', true, { buf = M._state.sidebar_buf })

  local line_count = vim.api.nvim_buf_line_count(M._state.sidebar_buf)
  local last_line = vim.api.nvim_buf_get_lines(M._state.sidebar_buf, line_count - 1, line_count, false)[1]

  -- If buffer is empty (just one empty line), replace it
  if line_count == 1 and last_line == '' then
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, 0, 1, false, lines)
  else
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, -1, -1, false, lines)
  end

  vim.api.nvim_set_option_value('modifiable', false, { buf = M._state.sidebar_buf })

  -- Scroll to bottom if sidebar is visible
  if M.is_sidebar_open() then
    local new_count = vim.api.nvim_buf_line_count(M._state.sidebar_buf)
    vim.api.nvim_win_set_cursor(M._state.sidebar_win, { new_count, 0 })
  end
end

--- Update the last assistant message (for streaming)
---@param text string
function M.update_last_message(text)
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end

  -- Find the last "**Claude:**" marker and replace everything after it
  local lines = vim.api.nvim_buf_get_lines(M._state.sidebar_buf, 0, -1, false)
  local last_claude_line = nil

  for i = #lines, 1, -1 do
    if lines[i]:match '^%*%*Claude:%*%*' then
      last_claude_line = i
      break
    end
  end

  if last_claude_line then
    local new_lines = vim.split(text .. '\n', '\n', { plain = true })

    vim.api.nvim_set_option_value('modifiable', true, { buf = M._state.sidebar_buf })
    vim.api.nvim_buf_set_lines(M._state.sidebar_buf, last_claude_line, -1, false, new_lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = M._state.sidebar_buf })

    -- Scroll to bottom
    if M.is_sidebar_open() then
      local new_count = vim.api.nvim_buf_line_count(M._state.sidebar_buf)
      vim.api.nvim_win_set_cursor(M._state.sidebar_win, { new_count, 0 })
    end
  end
end

--- Clear the conversation buffer
function M.clear()
  if not M._state.sidebar_buf or not vim.api.nvim_buf_is_valid(M._state.sidebar_buf) then
    return
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = M._state.sidebar_buf })
  vim.api.nvim_buf_set_lines(M._state.sidebar_buf, 0, -1, false, {})
  vim.api.nvim_set_option_value('modifiable', false, { buf = M._state.sidebar_buf })
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

    vim.api.nvim_win_close(win, true)
    M._state.input_win = nil
    M._state.input_buf = nil
    vim.cmd 'stopinsert'

    if callback and input ~= '' then
      callback(input)
    elseif callback then
      callback(nil)
    end
  end, opts)

  -- Cancel with Escape
  vim.keymap.set({ 'i', 'n' }, '<Esc>', function()
    vim.api.nvim_win_close(win, true)
    M._state.input_win = nil
    M._state.input_buf = nil
    vim.cmd 'stopinsert'
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
end

return M
