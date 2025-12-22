local M = {}

local api = vim.api
local ui = require("ai-companion.ui")
local api_service = require("ai-companion.api")

function M.setup()
  local ns = api.nvim_create_namespace("ai-companion-key-listener")

  vim.on_key(function(key)
    if key == "\v" then
      ui.close_inline_command()

      vim.ui.input({ prompt = "Enter prompt:" }, function(input)
        if input and input ~= "" then
          local selected_text = ui.get_selected_text()
          api_service.get_response(selected_text, input)
          vim.cmd("stopinsert")
        end
      end)
    end
  end, ns)
end

return M
