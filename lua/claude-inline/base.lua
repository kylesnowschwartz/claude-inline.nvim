local M = {}

local config = require 'claude-inline.config'

local function toggle_terminal_callback()
  -- Lazy require to avoid circular dependency
  require('claude-inline').toggle_terminal()
end

function M.setup()
  local keymaps = {
    { 'n', config.mappings.toggle_terminal, toggle_terminal_callback, 'Toggle Claude terminal.' },
  }

  for _, map in ipairs(keymaps) do
    vim.keymap.set(map[1], map[2], map[3], { desc = map[4] })
  end
end

return M
