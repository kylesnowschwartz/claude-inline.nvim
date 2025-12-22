local M = {}

local api = vim.api
local prompts = require("ai-companion.prompts")
local config = require("ai-companion.config")

local function set_buffer_lines(lines)
  if api.nvim_buf_is_valid(0) then
    api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end
end

function M.get_response(selected_text, input)
  local instruction = input
  local prompt_text = instruction .. "\n below is the selected code, \n```" .. selected_text .. "```"

  local cfg = config.config or {}
  local api_key = cfg.api_key or os.getenv("OPENAI_API_KEY")
  if not api_key or api_key == "" then
    vim.notify("OPENAI API KEY is missing", vim.log.levels.ERROR)
    vim.ui.input({ prompt = "Enter openai API key:" }, function(key)
      if key and key ~= "" then
        config.setup({ api_key = key })
        M.get_response(selected_text, instruction)
      end
    end)
    return
  end

  local model = cfg.model or "gpt-4.1-mini"

  local payload = vim.json.encode({
    model = model,
    input = {
      {
        role = "system",
        content = prompts.system_prompt,
      },
      {
        role = "user",
        content = prompt_text,
      },
    },
  })

  vim.system({
    "curl",
    "-s",
    "-X",
    "POST",
    "-H",
    "Content-Type: application/json",
    "-H",
    "Authorization: Bearer " .. api_key,
    "-d",
    payload,
    "https://api.openai.com/v1/responses",
  }, {
    text = true,
  }, function(res)
    local data = vim.json.decode(res.stdout)
    local response_code = data
        and data.output
        and data.output[2]
        and data.output[2].content
        and data.output[2].content[1]
        and data.output[2].content[1].text

    if not response_code then
      vim.schedule(function()
        vim.notify("Failed to parse OpenAI response", vim.log.levels.ERROR)
      end)
      return
    end

    local lines = vim.split(response_code, "\n", { plain = true })
    vim.schedule(function()
      set_buffer_lines(lines)
    end)
  end)
end

return M
