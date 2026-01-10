local config = require 'cursor-inline.config'
local ui = require 'cursor-inline.ui'
local base = require 'cursor-inline.base'
local autocmd = require 'cursor-inline.autocmd'
local lockfile = require 'cursor-inline.lockfile'

local M = {}

function M.setup(opts)
  config.setup(opts or {})
  ui.setup()
  autocmd.setup()
  base.setup()
end

---Find a running Claude Code instance and return connection info
---@return table|nil info { port, auth_token, workspace_folders } or nil if none found
function M.find_claude()
  local info, err = lockfile.get_connection_info_for_workspace()

  if not info then
    vim.notify('No Claude Code instance found: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
    return nil
  end

  return info
end

---List all running Claude Code instances
---@return table instances Array of instance info
function M.list_claude_instances()
  return lockfile.find_claude_instances()
end

return M
