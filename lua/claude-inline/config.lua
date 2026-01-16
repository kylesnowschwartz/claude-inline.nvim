--- Configuration for Claude Code inline editing.
local M = {}

M.mappings = {
  open_input = '<leader>e',
  accept_response = '<leader>y',
  deny_response = '<leader>n',
  toggle_terminal = '<leader>cc',
}

M.provider = {
  name = 'claude',
  model = 'claude-sonnet-4-20250514',
}

M.setup = function(opts)
  local provider = opts.provider or {}
  local mappings = opts.mappings or {}
  M.provider = vim.tbl_deep_extend('force', M.provider, provider)
  M.mappings = vim.tbl_deep_extend('force', M.mappings, mappings)
end

return M
