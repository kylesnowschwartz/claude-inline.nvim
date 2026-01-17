--- Health checks for claude-inline.nvim
local M = {}

local H = vim.health

function M.check()
  H.start("claude-inline.nvim")

  -- Check Claude CLI availability
  if vim.fn.executable("claude") == 1 then
    local result = vim.fn.system({ "claude", "--version" })
    local version = result:match("claude/([%d%.]+)") or "unknown"
    H.ok(string.format("Claude CLI found (version: %s)", version))
  else
    H.error("Claude CLI not found. Install: https://github.com/anthropics/claude-code")
  end

  -- Check configuration state
  local ok, config = pcall(require, "claude-inline.config")
  if ok and config.options and next(config.options) then
    H.ok("Configuration loaded")
  else
    H.warn('Not initialized. Call require("claude-inline").setup()')
  end

  -- Check TreeSitter markdown
  local ts_ok = pcall(vim.treesitter.language.add, "markdown")
  if ts_ok then
    H.ok("TreeSitter markdown parser available")
  else
    H.warn("TreeSitter markdown not found. Sidebar highlighting limited.")
  end
end

return M
