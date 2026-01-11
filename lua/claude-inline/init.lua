local config = require 'claude-inline.config'
local ui = require 'claude-inline.ui'
local base = require 'claude-inline.base'
local autocmd = require 'claude-inline.autocmd'
local lockfile = require 'claude-inline.lockfile'
local websocket = require 'claude-inline.websocket'
local terminal = require 'claude-inline.terminal'
local tools = require 'claude-inline.tools'
local client_manager = require 'claude-inline.websocket.client'

local M = {}

-- Initialize global table for deferred responses (coroutine-based blocking tools)
_G.claude_deferred_responses = _G.claude_deferred_responses or {}

---Send a JSON-RPC response to a client
---@param client table The WebSocket client
---@param id number|string|nil The request ID
---@param result table|nil The result (for success)
---@param err table|nil The error (for failure)
local function send_response(client, id, result, err)
  local response = {
    jsonrpc = '2.0',
    id = id,
  }

  if err then
    response.error = err
  else
    response.result = result
  end

  local json = vim.json.encode(response)
  client_manager.send_message(client, json)
end

---Handle JSON-RPC messages from Claude Code
---@param client table The WebSocket client
---@param message table Parsed JSON-RPC message
local function handle_jsonrpc(client, message)
  local method = message.method
  local id = message.id
  local params = message.params or {}

  -- tools/list - Return available tools
  if method == 'tools/list' then
    local tool_list = tools.get_tool_list()
    send_response(client, id, { tools = tool_list }, nil)
    return
  end

  -- tools/call - Execute a tool
  if method == 'tools/call' then
    local result = tools.handle_invoke(client, params)

    -- Check for deferred response (blocking tool like openDiff)
    if result._deferred then
      -- Store response sender for when coroutine resumes
      local co_key = tostring(result.coroutine)
      _G.claude_deferred_responses[co_key] = function(final_result)
        vim.schedule(function()
          if final_result.error then
            send_response(client, id, nil, final_result.error)
          else
            send_response(client, id, final_result.result or final_result, nil)
          end
        end)
      end
      return
    end

    -- Immediate response
    if result.error then
      send_response(client, id, nil, result.error)
    else
      send_response(client, id, result.result, nil)
    end
    return
  end

  -- Unknown method
  send_response(client, id, nil, {
    code = -32601,
    message = 'Method not found: ' .. (method or 'nil'),
  })
end

function M.setup(opts)
  config.setup(opts or {})
  ui.setup()
  autocmd.setup()
  base.setup()
  tools.setup()
end

---Start the WebSocket server and create lock file
---@param opts table|nil Optional settings: { on_message, on_connect, on_disconnect, on_error }
---@return boolean success Whether server started successfully
---@return string|nil error Error message if failed
function M.start(opts)
  opts = opts or {}

  if websocket.is_running() then
    vim.notify('Server already running on port ' .. websocket.get_port(), vim.log.levels.WARN)
    return false, 'Server already running'
  end

  -- Generate auth token
  local auth_token = lockfile.generate_auth_token()

  -- Start the WebSocket server
  local success, port_or_error = websocket.start {
    auth_token = auth_token,
    on_message = function(client, message)
      -- Parse JSON-RPC message
      local ok, parsed = pcall(vim.json.decode, message)
      if ok then
        -- Route through MCP handler
        vim.schedule(function()
          handle_jsonrpc(client, parsed)
        end)
        -- Also call user callback if provided
        if opts.on_message then
          opts.on_message(client, parsed)
        end
      end
    end,
    on_connect = function(client)
      vim.schedule(function()
        vim.notify('Claude Code connected (client: ' .. client.id .. ')', vim.log.levels.INFO)
        if opts.on_connect then
          opts.on_connect(client)
        end
      end)
    end,
    on_disconnect = function(client, code, reason)
      vim.schedule(function()
        vim.notify('Claude Code disconnected: ' .. (reason or 'closed'), vim.log.levels.INFO)
        if opts.on_disconnect then
          opts.on_disconnect(client, code, reason)
        end
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        vim.notify('WebSocket error: ' .. err, vim.log.levels.ERROR)
        if opts.on_error then
          opts.on_error(err)
        end
      end)
    end,
  }

  if not success then
    vim.notify('Failed to start server: ' .. port_or_error, vim.log.levels.ERROR)
    return false, port_or_error
  end

  local port = port_or_error

  -- Create lock file for Claude Code to discover us
  local lock_success, lock_result, _ = lockfile.create(port, auth_token)
  if not lock_success then
    websocket.stop()
    vim.notify('Failed to create lock file: ' .. lock_result, vim.log.levels.ERROR)
    return false, lock_result
  end

  vim.notify('Server started on port ' .. port .. ' (lock file: ' .. lock_result .. ')', vim.log.levels.INFO)
  return true, nil
end

---Stop the WebSocket server and remove lock file
function M.stop()
  if not websocket.is_running() then
    vim.notify('Server not running', vim.log.levels.WARN)
    return
  end

  local port = websocket.get_port()

  -- Remove lock file first
  if port then
    lockfile.remove(port)
  end

  -- Stop server
  websocket.stop()

  vim.notify('Server stopped', vim.log.levels.INFO)
end

---Check if server is running
---@return boolean running True if server is running
function M.is_running()
  return websocket.is_running()
end

---Get server status
---@return table status Server status information
function M.get_status()
  return websocket.get_status()
end

---Send a JSON-RPC notification to all connected clients
---@param method string The method name
---@param params table|nil The parameters
function M.broadcast(method, params)
  if not websocket.is_running() then
    return
  end

  local message = vim.json.encode {
    jsonrpc = '2.0',
    method = method,
    params = params or vim.empty_dict(),
  }

  websocket.broadcast(message)
end

---Find a running Claude Code instance (other IDEs' servers)
---For debugging/introspection, not for connecting
---@return table|nil info { port, auth_token, workspace_folders } or nil if none found
function M.find_claude()
  local info, err = lockfile.get_connection_info_for_workspace()

  if not info then
    vim.notify('No Claude Code instance found: ' .. (err or 'unknown error'), vim.log.levels.WARN)
    return nil
  end

  return info
end

---List all running Claude Code instances (other IDEs' servers)
---@return table instances Array of instance info
function M.list_claude_instances()
  return lockfile.find_claude_instances()
end

---Open the Claude terminal sidebar
---Auto-starts the WebSocket server if not already running
function M.open_terminal()
  -- Auto-start server if not running
  if not websocket.is_running() then
    local success, err = M.start()
    if not success then
      vim.notify('Failed to start server for terminal: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
      return
    end
  end

  local port = websocket.get_port()
  if not port then
    vim.notify('Server port not available', vim.log.levels.ERROR)
    return
  end

  terminal.open(port, true)
end

---Close the Claude terminal sidebar
function M.close_terminal()
  terminal.close()
end

---Toggle the Claude terminal sidebar visibility
function M.toggle_terminal()
  -- Auto-start server if not running
  if not websocket.is_running() then
    local success, err = M.start()
    if not success then
      vim.notify('Failed to start server for terminal: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
      return
    end
  end

  local port = websocket.get_port()
  if not port then
    vim.notify('Server port not available', vim.log.levels.ERROR)
    return
  end

  terminal.toggle(port)
end

---Check if the Claude terminal is open
---@return boolean is_open True if terminal is visible
function M.is_terminal_open()
  return terminal.is_open()
end

return M
