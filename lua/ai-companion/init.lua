local M = {}

local config = require("ai-companion.config")
local autocmd = require("ai-companion.autocmd")
local ui = require("ai-companion.ui")

function M.setup(opts)
  config.setup(opts or {})
  ui.setup()
  autocmd.setup()
end

return M

