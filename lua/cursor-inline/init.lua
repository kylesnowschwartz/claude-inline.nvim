local config = require 'cursor-inline.config'
local ui = require 'cursor-inline.ui'
local base = require 'cursor-inline.base'
local autocmd = require 'cursor-inline.autocmd'
local lockfile = require 'cursor-inline.lockfile'
local websocket = require 'cursor-inline.websocket'

local M = {}

function M.setup(opts)
  config.setup(opts or {})
  ui.setup()
  autocmd.setup()
  base.setup()
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
      if ok and opts.on_message then
        opts.on_message(client, parsed)
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

return M
