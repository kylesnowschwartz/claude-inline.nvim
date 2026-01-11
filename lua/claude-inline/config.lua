--- Configuration for Claude Code inline editing.
local M = {}

M.mappings = {
  toggle_terminal = '<leader>cc',
}

M.setup = function(opts)
  local mappings = opts.mappings or {}
  M.mappings = vim.tbl_deep_extend('force', M.mappings, mappings)
end

return M
