local M = {}

local ui = require("ai-companion.ui")
local core_api = require("ai-companion.api")
local config = require("ai-companion.config")

local function open_input_callback()
  ui.close_inline_command()
  vim.ui.input({ prompt = "Enter prompt:" }, function(input)
    if input and input ~= "" then
      core_api.get_response(input)
      vim.cmd("stopinsert")
    end
  end)
end

function M.setup()
  vim.keymap.set("v", config.mappings.open_input, open_input_callback, { desc = "Opening the input prompt." })
  vim.keymap.set("n", config.mappings.deny_response, core_api.reject_api_response,
    { desc = "Declining the API response." })
  vim.keymap.set("n", config.mappings.accept_response, core_api.accept_api_response,
    { desc = "Accepting the API response." })
end

return M
