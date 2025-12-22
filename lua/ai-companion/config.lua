local M = {}

M.config = {
  model = "gpt-4.1-mini",
  api_key = nil,
}

M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts)
end


return M
