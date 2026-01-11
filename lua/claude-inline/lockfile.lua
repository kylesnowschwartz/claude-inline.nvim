---@brief [[
--- Lock file management for Claude Code integration.
--- This module handles both creation and discovery of lock files
--- at ~/.claude/ide/*.lock for Claude Code CLI integration.
---@brief ]]
---@module 'claude-inline.lockfile'
local M = {}

---Path to the lock file directory
---@return string lock_dir The path to the lock file directory
local function get_lock_dir()
  local claude_config_dir = os.getenv 'CLAUDE_CONFIG_DIR'
  if claude_config_dir and claude_config_dir ~= '' then
    return vim.fn.expand(claude_config_dir .. '/ide')
  else
    return vim.fn.expand '~/.claude/ide'
  end
end

M.lock_dir = get_lock_dir()

-- Track if random seed has been initialized
local random_initialized = false

---Generate a UUID v4 authentication token
---Pattern copied from claudecode.nvim/lua/claudecode/lockfile.lua
---@return string uuid A randomly generated UUID string
local function generate_auth_token()
  -- Initialize random seed only once
  if not random_initialized then
    local seed = os.time() + vim.fn.getpid()
    -- Add more entropy if available
    if vim.loop and vim.loop.hrtime then
      seed = seed + (vim.loop.hrtime() % 1000000)
    end
    math.randomseed(seed)

    -- Call math.random a few times to "warm up" the generator
    for _ = 1, 10 do
      math.random()
    end
    random_initialized = true
  end

  -- Generate UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  local uuid = template:gsub('[xy]', function(c)
    local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
    return string.format('%x', v)
  end)

  return uuid
end

---Generate a new authentication token (public interface)
---@return string auth_token A newly generated authentication token
function M.generate_auth_token()
  return generate_auth_token()
end

---Get workspace folders for the lock file
---@return table Array of workspace folder paths
function M.get_workspace_folders()
  local folders = {}

  -- Add current working directory
  table.insert(folders, vim.fn.getcwd())

  -- Get LSP workspace folders if available
  local clients = {}
  if vim.lsp then
    if vim.lsp.get_clients then
      clients = vim.lsp.get_clients()
    elseif vim.lsp.get_active_clients then
      clients = vim.lsp.get_active_clients()
    end
  end

  for _, client in pairs(clients) do
    if client.config and client.config.workspace_folders then
      for _, ws in ipairs(client.config.workspace_folders) do
        local path = ws.uri
        if path:sub(1, 7) == 'file://' then
          path = path:sub(8)
        end

        -- Check if already in the list
        local exists = false
        for _, folder in ipairs(folders) do
          if folder == path then
            exists = true
            break
          end
        end

        if not exists then
          table.insert(folders, path)
        end
      end
    end
  end

  return folders
end

---Create the lock file for a specified WebSocket port
---@param port number The port number for the WebSocket server
---@param auth_token? string Optional pre-generated auth token (generates new one if not provided)
---@return boolean success Whether the operation was successful
---@return string result_or_error The lock file path if successful, or error message if failed
---@return string? auth_token The authentication token if successful
function M.create(port, auth_token)
  if not port or type(port) ~= 'number' then
    return false, 'Invalid port number'
  end

  if port < 1 or port > 65535 then
    return false, 'Port number out of valid range (1-65535): ' .. tostring(port)
  end

  -- Ensure lock directory exists
  local ok, err = pcall(function()
    return vim.fn.mkdir(M.lock_dir, 'p')
  end)

  if not ok then
    return false, 'Failed to create lock directory: ' .. (err or 'unknown error')
  end

  local lock_path = M.lock_dir .. '/' .. port .. '.lock'

  -- Generate auth token if not provided
  if not auth_token then
    auth_token = generate_auth_token()
  end

  -- Prepare lock file content
  local lock_content = {
    pid = vim.fn.getpid(),
    workspaceFolders = M.get_workspace_folders(),
    ideName = 'Neovim',
    transport = 'ws',
    authToken = auth_token,
  }

  local json
  local ok_json, json_err = pcall(function()
    json = vim.json.encode(lock_content)
    return json
  end)

  if not ok_json or not json then
    return false, 'Failed to encode lock file content: ' .. (json_err or 'unknown error')
  end

  local file = io.open(lock_path, 'w')
  if not file then
    return false, 'Failed to create lock file: ' .. lock_path
  end

  local write_ok, write_err = pcall(function()
    file:write(json)
    file:close()
  end)

  if not write_ok then
    pcall(function()
      file:close()
    end)
    return false, 'Failed to write lock file: ' .. (write_err or 'unknown error')
  end

  return true, lock_path, auth_token
end

---Remove the lock file for the given port
---@param port number The port number of the WebSocket server
---@return boolean success Whether the operation was successful
---@return string? error Error message if operation failed
function M.remove(port)
  if not port or type(port) ~= 'number' then
    return false, 'Invalid port number'
  end

  local lock_path = M.lock_dir .. '/' .. port .. '.lock'

  if vim.fn.filereadable(lock_path) == 0 then
    return true -- Already removed, that's fine
  end

  local ok, err = pcall(function()
    return os.remove(lock_path)
  end)

  if not ok then
    return false, 'Failed to remove lock file: ' .. (err or 'unknown error')
  end

  return true
end

---Parse a lock file and extract connection info
---@param path string Absolute path to the lock file
---@return table|nil lock_data Parsed lock file data or nil on error
---@return string|nil error Error message if parsing failed
function M.parse_lock_file(path)
  if vim.fn.filereadable(path) == 0 then
    return nil, 'Lock file does not exist: ' .. path
  end

  local file = io.open(path, 'r')
  if not file then
    return nil, 'Failed to open lock file: ' .. path
  end

  local content = file:read '*all'
  file:close()

  if not content or content == '' then
    return nil, 'Lock file is empty: ' .. path
  end

  local ok, lock_data = pcall(vim.json.decode, content)
  if not ok or type(lock_data) ~= 'table' then
    return nil, 'Failed to parse lock file JSON: ' .. path
  end

  return lock_data, nil
end

---Check if a process with given PID is still running
---@param pid number Process ID to check
---@return boolean running True if process is running
local function is_process_running(pid)
  if not pid or type(pid) ~= 'number' then
    return false
  end

  -- Use kill -0 to check if process exists (doesn't actually send signal)
  local result = vim.fn.system('kill -0 ' .. pid .. ' 2>/dev/null; echo $?')
  local exit_code = tonumber(vim.fn.trim(result))
  return exit_code == 0
end

---Find all running Claude Code instances
---@return table instances Array of { port, auth_token, workspace_folders, pid, lock_path }
function M.find_claude_instances()
  local instances = {}

  -- Check if lock directory exists
  if vim.fn.isdirectory(M.lock_dir) == 0 then
    return instances
  end

  -- Scan for .lock files
  local lock_files = vim.fn.glob(M.lock_dir .. '/*.lock', false, true)
  if type(lock_files) ~= 'table' then
    return instances
  end

  for _, lock_path in ipairs(lock_files) do
    local lock_data, err = M.parse_lock_file(lock_path)
    if lock_data and not err then
      -- Extract port from filename (e.g., "12345.lock" -> 12345)
      local filename = vim.fn.fnamemodify(lock_path, ':t')
      local port = tonumber(filename:match '^(%d+)%.lock$')

      if port and lock_data.authToken then
        -- Verify the process is still running
        local pid = lock_data.pid
        if is_process_running(pid) then
          table.insert(instances, {
            port = port,
            auth_token = lock_data.authToken,
            workspace_folders = lock_data.workspaceFolders or {},
            pid = pid,
            lock_path = lock_path,
            ide_name = lock_data.ideName,
            transport = lock_data.transport,
          })
        end
      end
    end
  end

  return instances
end

---Get connection info for the first available Claude Code instance
---@return table|nil info { port, auth_token, workspace_folders } or nil if none found
---@return string|nil error Error message if no instance found
function M.get_connection_info()
  local instances = M.find_claude_instances()

  if #instances == 0 then
    return nil, 'No running Claude Code instance found'
  end

  -- Return the first instance found
  local instance = instances[1]
  return {
    port = instance.port,
    auth_token = instance.auth_token,
    workspace_folders = instance.workspace_folders,
  }, nil
end

---Get connection info for Claude Code instance matching current workspace
---@return table|nil info { port, auth_token, workspace_folders } or nil if none found
---@return string|nil error Error message if no instance found
function M.get_connection_info_for_workspace()
  local instances = M.find_claude_instances()

  if #instances == 0 then
    return nil, 'No running Claude Code instance found'
  end

  local cwd = vim.fn.getcwd()

  -- Try to find an instance matching current workspace
  for _, instance in ipairs(instances) do
    for _, folder in ipairs(instance.workspace_folders) do
      if folder == cwd or cwd:find(folder, 1, true) == 1 then
        return {
          port = instance.port,
          auth_token = instance.auth_token,
          workspace_folders = instance.workspace_folders,
        },
          nil
      end
    end
  end

  -- Fallback to first instance if no workspace match
  local instance = instances[1]
  return {
    port = instance.port,
    auth_token = instance.auth_token,
    workspace_folders = instance.workspace_folders,
  }, nil
end

return M
