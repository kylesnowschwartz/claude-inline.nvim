--- Input prompt for claude-inline.nvim
--- Floating window for user input

local state = require 'claude-inline.ui.state'

local M = {}

--- Close input window and cleanup state
---@param win number Window handle to close
local function close(win)
  vim.api.nvim_win_close(win, true)
  state.input_win = nil
  state.input_buf = nil
  vim.cmd 'stopinsert'
end

--- Show input prompt window
---@param callback fun(input: string|nil)
function M.show(callback)
  -- Close existing input if open
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, true)
  end

  local config = state.config.ui.input

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

  state.input_win = win
  state.input_buf = buf

  vim.cmd 'startinsert'

  -- Keymaps
  local opts = { buffer = buf, nowait = true, noremap = true, silent = true }

  -- Accept input with Enter
  vim.keymap.set('i', '<CR>', function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(lines, '\n')
    input = vim.trim(input)

    close(win)

    if callback and input ~= '' then
      callback(input)
    elseif callback then
      callback(nil)
    end
  end, opts)

  -- Cancel with Escape
  vim.keymap.set({ 'i', 'n' }, '<Esc>', function()
    close(win)
    if callback then
      callback(nil)
    end
  end, opts)
end

--- Close input window if open (for cleanup)
function M.close()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    close(state.input_win)
  end
end

return M
