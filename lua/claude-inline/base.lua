local M = {}

local ui = require 'claude-inline.ui'
local core_api = require 'claude-inline.api'
local config = require 'claude-inline.config'

local function open_input_callback()
  ui.close_inline_command()
  core_api.get_response()
end

local function toggle_terminal_callback()
  -- Lazy require to avoid circular dependency
  require('claude-inline').toggle_terminal()
end

function M.setup()
  local keymaps = {
    { 'v', config.mappings.open_input, open_input_callback, 'Opening the input prompt.' },
    { 'n', config.mappings.deny_response, core_api.reject_api_response, 'Declining the API response.' },
    { 'n', config.mappings.accept_response, core_api.accept_api_response, 'Accepting the API response.' },
    { 'n', config.mappings.toggle_terminal, toggle_terminal_callback, 'Toggle Claude terminal.' },
  }

  for _, map in ipairs(keymaps) do
    vim.keymap.set(map[1], map[2], map[3], { desc = map[4] })
  end
end

return M
