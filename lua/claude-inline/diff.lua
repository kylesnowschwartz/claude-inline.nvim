--- Diff module for Claude Code inline editing.
--- Provides native Neovim diff functionality with blocking operations.
local M = {}

---@type table<string, table> Active diff states keyed by tab_name
local active_diffs = {}

---@type number|nil Autocmd group ID
local autocmd_group

---Get or create the autocmd group for diff operations
---@return number autocmd_group The autocmd group ID
local function get_autocmd_group()
  if not autocmd_group then
    autocmd_group = vim.api.nvim_create_augroup('ClaudeInlineDiff', { clear = true })
  end
  return autocmd_group
end

---Find a suitable main editor window (excludes terminals, floating windows)
---@return number|nil win_id Window ID or nil if not found
local function find_main_editor_window()
  local windows = vim.api.nvim_list_wins()

  for _, win in ipairs(windows) do
    local buf = vim.api.nvim_win_get_buf(win)
    local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf })
    local win_config = vim.api.nvim_win_get_config(win)

    -- Skip floating windows
    local is_floating = win_config.relative and win_config.relative ~= ''
    -- Skip terminals
    local is_terminal = buftype == 'terminal' or buftype == 'prompt'

    if not is_floating and not is_terminal then
      return win
    end
  end

  return nil
end

---Detect filetype from a path
---@param path string The file path
---@return string|nil filetype The detected filetype or nil
local function detect_filetype(path)
  if vim.filetype and type(vim.filetype.match) == 'function' then
    local ok, ft = pcall(vim.filetype.match, { filename = path })
    if ok and ft and ft ~= '' then
      return ft
    end
  end

  -- Fallback to extension mapping
  local ext = path:match '%.([%w_%-]+)$' or ''
  local ext_map = {
    lua = 'lua',
    ts = 'typescript',
    js = 'javascript',
    jsx = 'javascriptreact',
    tsx = 'typescriptreact',
    py = 'python',
    go = 'go',
    rs = 'rust',
    c = 'c',
    h = 'c',
    cpp = 'cpp',
    hpp = 'cpp',
    md = 'markdown',
    sh = 'sh',
    json = 'json',
    yaml = 'yaml',
    yml = 'yaml',
    rb = 'ruby',
    ex = 'elixir',
    exs = 'elixir',
  }
  return ext_map[ext]
end

---Register autocmds for a specific diff
---@param tab_name string The diff identifier
---@param new_buffer number New file buffer ID
---@return table List of autocmd IDs
local function register_diff_autocmds(tab_name, new_buffer)
  local autocmd_ids = {}

  -- Handle :w command to accept diff changes
  autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = get_autocmd_group(),
    buffer = new_buffer,
    callback = function()
      M._resolve_diff_as_saved(tab_name, new_buffer)
      return true -- Prevent actual file write
    end,
  })

  -- Buffer deletion = rejection
  for _, event in ipairs { 'BufDelete', 'BufUnload', 'BufWipeout' } do
    autocmd_ids[#autocmd_ids + 1] = vim.api.nvim_create_autocmd(event, {
      group = get_autocmd_group(),
      buffer = new_buffer,
      callback = function()
        M._resolve_diff_as_rejected(tab_name)
      end,
    })
  end

  return autocmd_ids
end

---Resolve diff as saved (user accepted changes via :w)
---@param tab_name string The diff identifier
---@param buffer_id number The buffer that was saved
function M._resolve_diff_as_saved(tab_name, buffer_id)
  local diff_data = active_diffs[tab_name]
  if not diff_data or diff_data.status ~= 'pending' then
    return
  end

  -- Get content from buffer
  local content_lines = vim.api.nvim_buf_get_lines(buffer_id, 0, -1, false)
  local final_content = table.concat(content_lines, '\n')
  if #content_lines > 0 and vim.api.nvim_get_option_value('eol', { buf = buffer_id }) then
    final_content = final_content .. '\n'
  end

  local result = {
    content = {
      { type = 'text', text = 'FILE_SAVED' },
      { type = 'text', text = final_content },
    },
  }

  diff_data.status = 'saved'
  diff_data.result_content = result

  if diff_data.resolution_callback then
    diff_data.resolution_callback(result)
  end
end

---Resolve diff as rejected (user closed buffer)
---@param tab_name string The diff identifier
function M._resolve_diff_as_rejected(tab_name)
  local diff_data = active_diffs[tab_name]
  if not diff_data or diff_data.status ~= 'pending' then
    return
  end

  local result = {
    content = {
      { type = 'text', text = 'DIFF_REJECTED' },
      { type = 'text', text = tab_name },
    },
  }

  diff_data.status = 'rejected'
  diff_data.result_content = result

  if diff_data.resolution_callback then
    diff_data.resolution_callback(result)
  end
end

---Clean up diff state
---@param tab_name string The diff identifier
function M._cleanup_diff_state(tab_name)
  local diff_data = active_diffs[tab_name]
  if not diff_data then
    return
  end

  -- Clean up autocmds
  for _, autocmd_id in ipairs(diff_data.autocmd_ids or {}) do
    pcall(vim.api.nvim_del_autocmd, autocmd_id)
  end

  -- Close new diff window if still open
  if diff_data.new_window and vim.api.nvim_win_is_valid(diff_data.new_window) then
    pcall(vim.api.nvim_win_close, diff_data.new_window, true)
  end

  -- Turn off diff mode in original window
  if diff_data.original_window and vim.api.nvim_win_is_valid(diff_data.original_window) then
    vim.api.nvim_win_call(diff_data.original_window, function()
      vim.cmd 'diffoff'
    end)
  end

  -- Clean up the new buffer
  if diff_data.new_buffer and vim.api.nvim_buf_is_valid(diff_data.new_buffer) then
    pcall(vim.api.nvim_buf_delete, diff_data.new_buffer, { force = true })
  end

  active_diffs[tab_name] = nil
end

---Set up the blocking diff operation
---@param params table Parameters for the diff
---@param resolution_callback function Callback when diff resolves
function M._setup_blocking_diff(params, resolution_callback)
  local tab_name = params.tab_name
  local old_file_path = params.old_file_path
  local new_file_contents = params.new_file_contents

  local old_file_exists = vim.fn.filereadable(old_file_path) == 1
  local is_new_file = not old_file_exists

  -- Find a suitable window
  local target_window = find_main_editor_window()
  if not target_window then
    error {
      code = -32000,
      message = 'No suitable editor window found',
      data = 'Could not find a main editor window to display the diff',
    }
  end

  -- Check for unsaved changes
  if old_file_exists then
    local bufnr = vim.fn.bufnr(old_file_path)
    if bufnr ~= -1 and vim.api.nvim_get_option_value('modified', { buf = bufnr }) then
      error {
        code = -32000,
        message = 'Cannot create diff: file has unsaved changes',
        data = 'Please save (:w) or discard (:e!) changes to ' .. old_file_path,
      }
    end
  end

  -- Create the new buffer with proposed content
  local new_buffer = vim.api.nvim_create_buf(false, true)
  if new_buffer == 0 then
    error {
      code = -32000,
      message = 'Buffer creation failed',
      data = 'Could not create new content buffer',
    }
  end

  local new_name = is_new_file and (tab_name .. ' (NEW FILE - proposed)') or (tab_name .. ' (proposed)')
  vim.api.nvim_buf_set_name(new_buffer, new_name)

  local lines = vim.split(new_file_contents, '\n')
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines, #lines)
  end
  vim.api.nvim_buf_set_lines(new_buffer, 0, -1, false, lines)

  vim.api.nvim_set_option_value('buftype', 'acwrite', { buf = new_buffer })
  vim.api.nvim_set_option_value('modifiable', true, { buf = new_buffer })

  -- Set up the diff view
  vim.api.nvim_set_current_win(target_window)

  local original_buffer
  if is_new_file then
    -- Create empty buffer for new file
    original_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(original_buffer, old_file_path .. ' (NEW FILE)')
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = original_buffer })
    vim.api.nvim_set_option_value('modifiable', false, { buf = original_buffer })
    vim.api.nvim_win_set_buf(target_window, original_buffer)
  else
    vim.cmd('edit ' .. vim.fn.fnameescape(old_file_path))
    original_buffer = vim.api.nvim_win_get_buf(target_window)
  end

  vim.cmd 'diffthis'

  -- Create split for the new content
  vim.cmd 'rightbelow vsplit'
  local new_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_window, new_buffer)

  -- Set filetype for syntax highlighting
  local ft = detect_filetype(old_file_path)
  if ft then
    vim.api.nvim_set_option_value('filetype', ft, { buf = new_buffer })
  end

  vim.cmd 'diffthis'
  vim.cmd 'wincmd ='

  -- Register autocmds
  local autocmd_ids = register_diff_autocmds(tab_name, new_buffer)

  -- Store diff state
  active_diffs[tab_name] = {
    old_file_path = old_file_path,
    new_file_path = params.new_file_path,
    new_file_contents = new_file_contents,
    new_buffer = new_buffer,
    new_window = new_window,
    original_window = target_window,
    original_buffer = original_buffer,
    autocmd_ids = autocmd_ids,
    status = 'pending',
    resolution_callback = resolution_callback,
    is_new_file = is_new_file,
  }
end

---Blocking diff operation for MCP compliance
---@param old_file_path string Path to the original file
---@param new_file_path string Path to the new file (used for naming)
---@param new_file_contents string Contents of the new file
---@param tab_name string Name for the diff tab/view
---@return table response MCP-compliant response with content array
function M.open_diff_blocking(old_file_path, new_file_path, new_file_contents, tab_name)
  -- Check for existing diff with same tab_name
  if active_diffs[tab_name] then
    M._resolve_diff_as_rejected(tab_name)
    M._cleanup_diff_state(tab_name)
  end

  local co, is_main = coroutine.running()
  if not co or is_main then
    error {
      code = -32000,
      message = 'Internal server error',
      data = 'openDiff must run in coroutine context',
    }
  end

  local success, err = pcall(M._setup_blocking_diff, {
    old_file_path = old_file_path,
    new_file_path = new_file_path,
    new_file_contents = new_file_contents,
    tab_name = tab_name,
  }, function(result)
    -- Resume the coroutine with the result
    local resume_success, resume_result = coroutine.resume(co, result)
    if resume_success then
      -- Use global response sender
      local co_key = tostring(co)
      if _G.claude_deferred_responses and _G.claude_deferred_responses[co_key] then
        _G.claude_deferred_responses[co_key](resume_result)
        _G.claude_deferred_responses[co_key] = nil
      end
    end
  end)

  if not success then
    local error_msg = type(err) == 'table' and err.message or tostring(err)
    if type(err) == 'table' and err.code then
      error(err)
    else
      error {
        code = -32000,
        message = 'Error setting up diff',
        data = error_msg,
      }
    end
  end

  -- Yield and wait for user interaction
  local user_action_result = coroutine.yield()
  return user_action_result
end

---Close diff by tab name
---@param tab_name string The diff identifier
---@return boolean success True if diff was found and closed
function M.close_diff_by_tab_name(tab_name)
  local diff_data = active_diffs[tab_name]
  if not diff_data then
    return false
  end

  M._cleanup_diff_state(tab_name)
  return true
end

-- Clean up on Neovim exit
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = get_autocmd_group(),
  callback = function()
    for tab_name, _ in pairs(active_diffs) do
      M._cleanup_diff_state(tab_name)
    end
  end,
})

return M
