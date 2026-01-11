--- Native Neovim terminal for Claude Code CLI
--- @module 'claude-inline.terminal'

local M = {}

-- Terminal state (single instance per Neovim session)
local bufnr = nil
local winid = nil
local jobid = nil

-- Default configuration
local config = {
  split_side = 'right',
  split_width_percentage = 0.30,
  auto_close = true,
}

--- Cleanup terminal state
local function cleanup_state()
  bufnr = nil
  winid = nil
  jobid = nil
end

--- Check if terminal buffer and window are valid
--- @return boolean valid True if terminal is valid
local function is_valid()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    cleanup_state()
    return false
  end

  -- If buffer is valid but window is invalid, try to find a window displaying this buffer
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    local windows = vim.api.nvim_list_wins()
    for _, win in ipairs(windows) do
      if vim.api.nvim_win_get_buf(win) == bufnr then
        winid = win
        return true
      end
    end
    -- Buffer exists but no window displays it (hidden)
    return true
  end

  return true
end

--- Check if terminal is currently visible in a window
--- @return boolean visible True if terminal is visible
local function is_visible()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      winid = win
      return true
    end
  end

  winid = nil
  return false
end

--- Create the terminal split window
--- @param effective_config table Configuration to use
--- @return number new_winid The created window ID
local function create_split(effective_config)
  local original_win = vim.api.nvim_get_current_win()
  local width = math.floor(vim.o.columns * effective_config.split_width_percentage)
  local full_height = vim.o.lines

  local placement = effective_config.split_side == 'left' and 'topleft ' or 'botright '

  vim.cmd(placement .. width .. 'vsplit')
  local new_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(new_winid, full_height)

  return new_winid, original_win
end

--- Open the terminal with Claude CLI
--- @param port number WebSocket server port for Claude to connect to
--- @param focus boolean|nil Whether to focus the terminal (default true)
--- @return boolean success Whether terminal opened successfully
local function open_terminal(port, focus)
  focus = focus == nil or focus

  if is_valid() then
    if focus and winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_set_current_win(winid)
      vim.cmd 'startinsert'
    end
    return true
  end

  local original_win = vim.api.nvim_get_current_win()
  local new_winid
  new_winid, original_win = create_split(config)

  vim.api.nvim_win_call(new_winid, function()
    vim.cmd 'enew'
  end)

  -- Environment variables for Claude CLI to discover our WebSocket server
  local env_table = {
    ENABLE_IDE_INTEGRATION = 'true',
    FORCE_CODE_TERMINAL = 'true',
    CLAUDE_CODE_SSE_PORT = tostring(port),
  }

  jobid = vim.fn.termopen({ 'claude' }, {
    env = env_table,
    on_exit = function(job_id, _, _)
      vim.schedule(function()
        if job_id == jobid then
          local current_winid = winid
          local current_bufnr = bufnr

          cleanup_state()

          if not config.auto_close then
            return
          end

          if current_winid and vim.api.nvim_win_is_valid(current_winid) then
            if current_bufnr and vim.api.nvim_buf_is_valid(current_bufnr) then
              if vim.api.nvim_win_get_buf(current_winid) == current_bufnr then
                vim.api.nvim_win_close(current_winid, true)
              end
            else
              vim.api.nvim_win_close(current_winid, true)
            end
          end
        end
      end)
    end,
  })

  if not jobid or jobid == 0 then
    vim.notify('Failed to open Claude terminal', vim.log.levels.ERROR)
    vim.api.nvim_win_close(new_winid, true)
    vim.api.nvim_set_current_win(original_win)
    cleanup_state()
    return false
  end

  winid = new_winid
  bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].bufhidden = 'hide'

  if focus then
    vim.api.nvim_set_current_win(winid)
    vim.cmd 'startinsert'
  else
    vim.api.nvim_set_current_win(original_win)
  end

  vim.notify('Claude terminal opened. Press Ctrl-\\ Ctrl-N to return to Normal mode.', vim.log.levels.INFO)
  return true
end

--- Hide the terminal window but keep the process running
local function hide_terminal()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) and winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, false)
    winid = nil
  end
end

--- Show a hidden terminal buffer in a new window
--- @param focus boolean|nil Whether to focus the terminal
--- @return boolean success Whether terminal was shown
local function show_hidden_terminal(focus)
  focus = focus == nil or focus

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  if is_visible() then
    if focus and winid then
      vim.api.nvim_set_current_win(winid)
      vim.cmd 'startinsert'
    end
    return true
  end

  local original_win = vim.api.nvim_get_current_win()
  local new_winid
  new_winid, original_win = create_split(config)

  vim.api.nvim_win_set_buf(new_winid, bufnr)
  winid = new_winid

  if focus then
    vim.api.nvim_set_current_win(winid)
    vim.cmd 'startinsert'
  else
    vim.api.nvim_set_current_win(original_win)
  end

  return true
end

--- Configure the terminal module
--- @param opts table|nil Configuration options
function M.setup(opts)
  if opts then
    config = vim.tbl_deep_extend('force', config, opts)
  end
end

--- Open the Claude terminal sidebar
--- Ensures the WebSocket server is running before opening
--- @param port number The WebSocket server port
--- @param focus boolean|nil Whether to focus the terminal (default true)
--- @return boolean success Whether terminal opened successfully
function M.open(port, focus)
  focus = focus == nil or focus

  if is_valid() then
    if not is_visible() then
      return show_hidden_terminal(focus)
    end
    if focus and winid then
      vim.api.nvim_set_current_win(winid)
      vim.cmd 'startinsert'
    end
    return true
  end

  return open_terminal(port, focus)
end

--- Close the Claude terminal
function M.close()
  if is_valid() then
    if winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
    cleanup_state()
  end
end

--- Toggle the Claude terminal visibility
--- @param port number The WebSocket server port
function M.toggle(port)
  local has_buffer = bufnr and vim.api.nvim_buf_is_valid(bufnr)
  local visible = has_buffer and is_visible()

  if visible then
    hide_terminal()
  elseif has_buffer then
    show_hidden_terminal(true)
  else
    open_terminal(port, true)
  end
end

--- Check if the terminal is currently open/visible
--- @return boolean is_open True if terminal is visible
function M.is_open()
  return is_visible()
end

--- Get the terminal buffer number
--- @return number|nil bufnr The buffer number or nil
function M.get_bufnr()
  if is_valid() then
    return bufnr
  end
  return nil
end

return M
