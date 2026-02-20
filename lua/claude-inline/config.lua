--- Configuration management for claude-inline.nvim
local M = {}

--- Default configuration
M.defaults = {
  keymaps = {
    send = "<leader>cs", -- Send prompt
    toggle = "<leader>ct", -- Toggle sidebar
    clear = "<leader>cx", -- Clear conversation
  },
  ui = {
    sidebar = {
      position = "right", -- 'left' or 'right'
      width = 0.4, -- 40% of editor width
    },
    input = {
      border = "rounded",
      width = 60,
      height = 3,
    },
    loading = {
      text = "Thinking...",
      spinner = { "|", "/", "-", "\\" },
      interval = 100,
    },
  },
  claude = {
    command = "claude",
    args = {
      "-p",
      "--input-format",
      "stream-json",
      "--output-format",
      "stream-json",
      "--verbose",
      "--model",
      "haiku",
    },
  },
  debug = false, -- Enable debug logging to /tmp/claude-inline-debug.log
}

--- Active configuration (set after setup)
M.options = {}

--- Merge user config with defaults
---@param user_config? table
---@return table
function M.setup(user_config)
  M.options = vim.tbl_deep_extend("force", M.defaults, user_config or {})
  return M.options
end

return M
