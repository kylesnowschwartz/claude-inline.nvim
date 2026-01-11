---@brief [[
--- WebSocket server for Claude Code IDE integration.
--- This module implements a WebSocket server that Claude Code CLI
--- connects to, following the same protocol as claudecode.nvim.
---@brief ]]
---@module 'claude-inline.websocket'
local client_manager = require 'claude-inline.websocket.client'
local utils = require 'claude-inline.websocket.utils'

local M = {}

---@class ServerState
---@field server table|nil The vim.loop TCP server handle
---@field port number|nil The port server is running on
---@field auth_token string|nil The authentication token for validating connections
---@field clients table<string, WebSocketClient> Table of connected clients
---@field on_message function|nil Callback for incoming messages
---@field on_connect function|nil Callback for new connections
---@field on_disconnect function|nil Callback for client disconnections
---@field on_error function|nil Callback for errors
---@field ping_timer table|nil Timer for sending pings

-- Server state
local state = {
  server = nil,
  port = nil,
  auth_token = nil,
  clients = {},
  on_message = nil,
  on_connect = nil,
  on_disconnect = nil,
  on_error = nil,
  ping_timer = nil,
}

---Find an available port by attempting to bind
---@param min_port number Minimum port to try
---@param max_port number Maximum port to try
---@return number|nil port Available port number, or nil if none found
local function find_available_port(min_port, max_port)
  if min_port > max_port then
    return nil
  end

  local ports = {}
  for i = min_port, max_port do
    table.insert(ports, i)
  end

  -- Shuffle the ports for better distribution
  utils.shuffle_array(ports)

  for _, port in ipairs(ports) do
    local test_server = vim.loop.new_tcp()
    if test_server then
      local success = test_server:bind('127.0.0.1', port)
      test_server:close()

      if success then
        return port
      end
    end
  end

  return nil
end

---Handle a new client connection
local function handle_new_connection()
  local client_tcp = vim.loop.new_tcp()
  if not client_tcp then
    if state.on_error then
      state.on_error 'Failed to create client TCP handle'
    end
    return
  end

  local accept_success, accept_err = state.server:accept(client_tcp)
  if not accept_success then
    if state.on_error then
      state.on_error('Failed to accept connection: ' .. (accept_err or 'unknown error'))
    end
    client_tcp:close()
    return
  end

  local client = client_manager.create_client(client_tcp)
  state.clients[client.id] = client

  client_tcp:read_start(function(err, data)
    if err then
      if state.on_error then
        state.on_error('Client read error: ' .. err)
      end
      M._remove_client(client)
      return
    end

    if not data then
      M._remove_client(client)
      return
    end

    client_manager.process_data(client, data, function(cl, message)
      if state.on_message then
        state.on_message(cl, message)
      end
    end, function(cl, code, reason)
      if state.on_disconnect then
        state.on_disconnect(cl, code, reason)
      end
      M._remove_client(cl)
    end, function(cl, error_msg)
      if state.on_error then
        state.on_error('Client ' .. cl.id .. ' error: ' .. error_msg)
      end
      M._remove_client(cl)
    end, state.auth_token)
  end)

  -- Notify about successful connection only after handshake
  -- The client.lua will set state to "connected" after handshake
  -- We'll check for this in the message handler
end

---Remove a client from the server
---@param client WebSocketClient The client to remove
function M._remove_client(client)
  if state.clients[client.id] then
    state.clients[client.id] = nil

    if not client.tcp_handle:is_closing() then
      client.tcp_handle:close()
    end
  end
end

---Start the WebSocket server
---@param opts table|nil Options: { port_range = {min, max}, auth_token, on_message, on_connect, on_disconnect, on_error }
---@return boolean success Whether server started successfully
---@return number|string port_or_error Port number or error message
function M.start(opts)
  if state.server then
    return false, 'Server already running'
  end

  opts = opts or {}
  local port_range = opts.port_range or { min = 10000, max = 65535 }

  local port = find_available_port(port_range.min, port_range.max)
  if not port then
    return false, 'No available ports in range ' .. port_range.min .. '-' .. port_range.max
  end

  local tcp_server = vim.loop.new_tcp()
  if not tcp_server then
    return false, 'Failed to create TCP server'
  end

  local bind_success, bind_err = tcp_server:bind('127.0.0.1', port)
  if not bind_success then
    tcp_server:close()
    return false, 'Failed to bind to port ' .. port .. ': ' .. (bind_err or 'unknown error')
  end

  local listen_success, listen_err = tcp_server:listen(128, function(err)
    if err then
      if state.on_error then
        state.on_error('Listen error: ' .. err)
      end
      return
    end

    handle_new_connection()
  end)

  if not listen_success then
    tcp_server:close()
    return false, 'Failed to listen on port ' .. port .. ': ' .. (listen_err or 'unknown error')
  end

  state.server = tcp_server
  state.port = port
  state.auth_token = opts.auth_token
  state.on_message = opts.on_message
  state.on_connect = opts.on_connect
  state.on_disconnect = opts.on_disconnect
  state.on_error = opts.on_error

  -- Start ping timer to keep connections alive
  M._start_ping_timer(30000)

  return true, port
end

---Stop the WebSocket server
---@return boolean success Whether server stopped successfully
---@return string|nil error Error message if any
function M.stop()
  if not state.server then
    return false, 'Server not running'
  end

  -- Stop ping timer
  if state.ping_timer then
    state.ping_timer:stop()
    state.ping_timer:close()
    state.ping_timer = nil
  end

  -- Close all clients
  for _, client in pairs(state.clients) do
    client_manager.close_client(client, 1001, 'Server shutting down')
  end

  state.clients = {}

  -- Close server
  if not state.server:is_closing() then
    state.server:close()
  end

  state.server = nil
  state.port = nil
  state.auth_token = nil

  return true
end

---Send a message to a specific client
---@param client_id string The client ID
---@param message string The message to send
---@param callback function|nil Optional callback
function M.send_to_client(client_id, message, callback)
  local client = state.clients[client_id]
  if not client then
    if callback then
      callback('Client not found: ' .. client_id)
    end
    return
  end

  client_manager.send_message(client, message, callback)
end

---Broadcast a message to all connected clients
---@param message string The message to broadcast
function M.broadcast(message)
  for _, client in pairs(state.clients) do
    client_manager.send_message(client, message)
  end
end

---Get the number of connected clients
---@return number count Number of connected clients
function M.get_client_count()
  local count = 0
  for _ in pairs(state.clients) do
    count = count + 1
  end
  return count
end

---Check if server is running
---@return boolean running True if server is running
function M.is_running()
  return state.server ~= nil
end

---Get server port
---@return number|nil port The server port or nil if not running
function M.get_port()
  return state.port
end

---Get server status
---@return table status Server status information
function M.get_status()
  if not state.server then
    return {
      running = false,
      port = nil,
      client_count = 0,
    }
  end

  local clients = {}
  for _, client in pairs(state.clients) do
    table.insert(clients, client_manager.get_client_info(client))
  end

  return {
    running = true,
    port = state.port,
    client_count = M.get_client_count(),
    clients = clients,
  }
end

---Start ping timer to keep connections alive
---@param interval number Ping interval in milliseconds
function M._start_ping_timer(interval)
  local timer = vim.loop.new_timer()
  if not timer then
    if state.on_error then
      state.on_error 'Failed to create ping timer'
    end
    return
  end

  local last_run = vim.loop.now()

  timer:start(interval, interval, function()
    local now = vim.loop.now()
    local elapsed = now - last_run

    -- Detect potential system sleep
    local is_wake_from_sleep = elapsed > (interval * 1.5)

    if is_wake_from_sleep then
      for _, client in pairs(state.clients) do
        if client.state == 'connected' then
          client.last_pong = now
        end
      end
    end

    for _, client in pairs(state.clients) do
      if client.state == 'connected' then
        if client_manager.is_client_alive(client, interval * 2) then
          client_manager.send_ping(client, 'ping')
        else
          client_manager.close_client(client, 1006, 'Connection timeout')
          M._remove_client(client)
        end
      end
    end

    last_run = now
  end)

  state.ping_timer = timer
end

---Get all connected clients
---@return table clients Table of clients by ID
function M.get_clients()
  return state.clients
end

---Get auth token (for lock file creation)
---@return string|nil auth_token The current auth token
function M.get_auth_token()
  return state.auth_token
end

return M
