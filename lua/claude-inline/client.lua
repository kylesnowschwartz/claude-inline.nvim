--- Claude CLI client for claude-inline.nvim
--- Handles process spawning, NDJSON parsing, and message passing
local M = {}

local uv = vim.uv or vim.loop

---@class ClaudeClient
---@field stdin uv.uv_pipe_t|nil
---@field stdout uv.uv_pipe_t|nil
---@field stderr uv.uv_pipe_t|nil
---@field process uv.uv_process_t|nil
---@field buffer string
---@field on_message fun(msg: table)|nil
---@field on_error fun(err: string)|nil
---@field config table

M._state = {
  stdin = nil,
  stdout = nil,
  stderr = nil,
  process = nil,
  buffer = '',
  on_message = nil,
  on_error = nil,
  config = nil,
}

--- Setup client with configuration
---@param config table
function M.setup(config)
  M._state.config = config
end

--- Check if client is running
---@return boolean
function M.is_running()
  return M._state.process ~= nil
end

--- Start the Claude CLI process
---@param on_message fun(msg: table) Callback for parsed messages
---@param on_error fun(err: string) Callback for errors
---@return boolean success
function M.start(on_message, on_error)
  if M.is_running() then
    return true
  end

  M._state.on_message = on_message
  M._state.on_error = on_error
  M._state.buffer = ''

  local stdin = uv.new_pipe(false)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  if not stdin or not stdout or not stderr then
    on_error 'Failed to create pipes'
    return false
  end

  local config = M._state.config.claude
  local args = vim.deepcopy(config.args or {})

  -- Inherit full environment (needed for Claude auth, HOME, etc.)
  local handle, pid = uv.spawn(config.command, {
    args = args,
    stdio = { stdin, stdout, stderr },
  }, function(code, signal)
    vim.schedule(function()
      M._cleanup()
      if code ~= 0 then
        local err = string.format('Claude process exited with code %d (signal %d)', code, signal)
        if M._state.on_error then
          M._state.on_error(err)
        end
      end
    end)
  end)

  if not handle then
    stdin:close()
    stdout:close()
    stderr:close()
    on_error 'Failed to spawn Claude process'
    return false
  end

  M._state.process = handle
  M._state.stdin = stdin
  M._state.stdout = stdout
  M._state.stderr = stderr

  -- Read stdout - NDJSON parsing
  stdout:read_start(function(err, data)
    if err then
      vim.schedule(function()
        if M._state.on_error then
          M._state.on_error('stdout error: ' .. err)
        end
      end)
      return
    end

    if data then
      M._state.buffer = M._state.buffer .. data

      -- Split on newlines and process complete JSON messages
      local lines = vim.split(M._state.buffer, '\n', { plain = true })
      M._state.buffer = lines[#lines] -- Keep incomplete line in buffer

      for i = 1, #lines - 1 do
        local line = vim.trim(lines[i])
        if line ~= '' then
          local ok, msg = pcall(vim.json.decode, line)
          if ok and M._state.on_message then
            vim.schedule(function()
              M._state.on_message(msg)
            end)
          end
        end
      end
    end
  end)

  -- Read stderr for debugging
  stderr:read_start(function(_, data)
    if data and M._state.on_error then
      vim.schedule(function()
        -- Only report actual errors, not debug info
        if data:match 'error' or data:match 'Error' then
          M._state.on_error('stderr: ' .. data)
        end
      end)
    end
  end)

  return true
end

--- Send a message to Claude
---@param prompt string The user's prompt
---@return boolean success
function M.send(prompt)
  if not M.is_running() or not M._state.stdin then
    return false
  end

  -- Format message according to stream-json protocol
  local message = {
    type = 'user',
    message = {
      role = 'user',
      content = {
        { type = 'text', text = prompt },
      },
    },
  }

  local json = vim.json.encode(message)
  M._state.stdin:write(json .. '\n')
  return true
end

--- Stop the Claude process
function M.stop()
  M._cleanup()
end

--- Internal cleanup function
function M._cleanup()
  if M._state.stdin and not M._state.stdin:is_closing() then
    M._state.stdin:close()
  end
  if M._state.stdout and not M._state.stdout:is_closing() then
    M._state.stdout:close()
  end
  if M._state.stderr and not M._state.stderr:is_closing() then
    M._state.stderr:close()
  end
  if M._state.process and not M._state.process:is_closing() then
    pcall(function()
      M._state.process:kill(15)
    end)
    M._state.process:close()
  end

  M._state.stdin = nil
  M._state.stdout = nil
  M._state.stderr = nil
  M._state.process = nil
  M._state.buffer = ''
end

return M
