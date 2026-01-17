-- Minimal Neovim configuration for tests
-- Run with: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

-- Add plugin to runtime path
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Disable unnecessary features for faster test execution
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Set up plenary if available (for test framework)
local plenary_path = vim.fn.stdpath 'data' .. '/site/pack/vendor/start/plenary.nvim'
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:append(plenary_path)
end

-- Load the plugin with test-friendly defaults
require('claude-inline').setup {
  debug = false,
  keymaps = {
    send = '<leader>cs',
    toggle = '<leader>ct',
    clear = '<leader>cx',
  },
  ui = {
    sidebar = { position = 'right', width = 0.4 },
    input = { border = 'rounded', width = 60, height = 3 },
    loading = { spinner = { '.' }, interval = 100, text = 'Thinking...' },
  },
}
