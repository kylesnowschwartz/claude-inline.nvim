local M = {}

local api = vim.api
local prompts = require("ai-companion.prompts")
local ui = require("ai-companion.ui")
local config = require("ai-companion.config")
local state = require("ai-companion.state")
local highlight = state.highlight

local function insert_generated_code(lines)
  local bufnr = state.main_bufnr or api.nvim_get_current_buf()
  if api.nvim_buf_is_valid(bufnr) then
    local start_row = vim.fn.line("'<") - 1
    highlight.new_code.start_row = start_row
    api.nvim_buf_set_lines(bufnr, start_row, start_row, false, lines)
  end
end

local function get_visual_range()
  local bufnr = state.main_bufnr or api.nvim_get_current_buf()
  local start_row, _ = unpack(vim.api.nvim_buf_get_mark(bufnr, "<"))
  local end_row, _ = unpack(vim.api.nvim_buf_get_mark(bufnr, ">"))
  return start_row - 1, end_row - 1
end

local function highlight_old_code()
  local bufnr = state.main_bufnr or api.nvim_get_current_buf()
  local ns = state.highlight.old_code.ns
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  highlight.old_code.start_row, highlight.old_code.end_row = get_visual_range()
  api.nvim_set_hl(0, state.highlight.old_code.hl_group, {
    bg = "#ea4859",
    blend = 80
  })
  state.highlight.old_code.id = api.nvim_buf_set_extmark(bufnr, ns, highlight.old_code.start_row, 0, {
    end_row = highlight.old_code.end_row + 1,
    hl_group = highlight.old_code.hl_group,
    hl_eol = true,
  })
  api.nvim_buf_set_lines(bufnr, highlight.old_code.end_row + 1, highlight.old_code.end_row + 1, false, { "" })
end

local function reset_states()
  local bufnr = state.main_bufnr
  local new_ns = state.highlight.new_code.ns
  local old_ns = state.highlight.old_code.ns
  vim.api.nvim_buf_clear_namespace(bufnr, new_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, old_ns, 0, -1)
  state.highlight.new_code.start_row = nil
  state.highlight.new_code.end_row = nil
  state.highlight.new_code.id = nil
  state.highlight.old_code.start_row = nil
  state.highlight.old_code.end_row = nil
  state.highlight.old_code.id = nil
  state.highlight.new_code.ns = api.nvim_create_namespace("NewCodeHighlight")
  state.highlight.old_code.ns = api.nvim_create_namespace("OldCodeHighlight")
end

M.get_old_code_region = function()
  local old_ns = state.highlight.old_code.ns
  local id = state.highlight.old_code.id
  if id == nil or old_ns == nil then return end
  local mark = api.nvim_buf_get_extmark_by_id(0, old_ns, id, { details = true })
  if not mark or vim.tbl_isempty(mark) then return end
  local sr, _, details = unpack(mark)
  if sr == nil or not details or details.end_row == nil then return end
  return sr, details.end_row
end


M.get_new_code_region = function()
  local new_ns = state.highlight.new_code.ns
  local id = state.highlight.new_code.id
  if id == nil or new_ns == nil then return end
  local mark = api.nvim_buf_get_extmark_by_id(0, new_ns, id, { details = true })
  if not mark or vim.tbl_isempty(mark) then return end
  local sr, _, details = unpack(mark)
  if sr == nil or not details or details.end_row == nil then return end
  return sr, details.end_row
end

local function highlight_new_inserted_code()
  local bufnr = state.main_bufnr or api.nvim_get_current_buf()
  local ns = state.highlight.new_code.ns
  highlight.new_code.end_row = vim.api.nvim_buf_get_mark(bufnr, "<")[1]
  local start_row = highlight.new_code.start_row
  api.nvim_set_hl(0, state.highlight.new_code.hl_group, {
    bg = "#199f5a",
    blend = 80
  })
  state.highlight.new_code.id = api.nvim_buf_set_extmark(bufnr, ns, start_row, 0, {
    end_row = highlight.new_code.end_row - 1,
    hl_group = highlight.new_code.hl_group,
    hl_eol = true,
  })
end

local function open_helper_commands_ui()
  local _, old_er = M.get_old_code_region()
  local accept_text = config.mappings.accept_response or ""
  local decline_text = config.mappings.deny_response or ""
  local accept_response = "Accept Edit (" .. accept_text .. ")"
  local decline_response = "Decline Edit (" .. decline_text .. ")"
  if old_er then
    state.wins.accept = ui.open_post_response_commands(old_er, accept_response, 48, 10)
    state.wins.deny = ui.open_post_response_commands(old_er, decline_response, 24, 20)
  end
end

function M.get_response(input)
  local instruction = input
  local selected_text = state.selected_text
  local prompt_text = instruction .. "\n below is the selected code, \n```" .. selected_text .. "```"
  local provider = config.provider or {}
  local api_key = os.getenv("OPENAI_API_KEY")
  if not api_key or api_key == "" then
    vim.notify("The " .. provider.name .. "API key is missing", vim.log.levels.ERROR)
    vim.ui.input({ prompt = "Enter " .. provider.name .. " API key:" }, function(key)
      if key and key ~= "" then
        vim.env.OPENAI_API_KEY = key
        M.get_response(instruction)
      end
    end)
    return
  end

  local model = provider.model or "gpt-4.1-mini"

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
    local response_code = data.output[1].content[1].text
    if not response_code then
      vim.schedule(function()
        vim.notify("Failed to parse OpenAI response", vim.log.levels.ERROR)
      end)
      return
    end

    local lines = vim.split(response_code, "\n", { plain = true })
    table.remove(lines, 1)
    table.remove(lines, #lines)
    vim.schedule(function()
      insert_generated_code(lines)
      highlight_new_inserted_code()
      highlight_old_code()
      open_helper_commands_ui()
    end)
  end)
end

M.accept_api_response = function()
  local new_sr, new_er = M.get_old_code_region()
  local bufnr = state.main_bufnr
  api.nvim_buf_set_lines(bufnr, new_sr, new_er, false, {})
  api.nvim_win_close(state.wins.accept, true)
  api.nvim_win_close(state.wins.deny, true)
  reset_states()
end

M.reject_api_response = function()
  local new_sr, new_er = M.get_new_code_region()
  local bufnr = state.main_bufnr
  api.nvim_buf_set_lines(bufnr, new_sr, new_er, false, {})
  api.nvim_win_close(state.wins.accept, true)
  api.nvim_win_close(state.wins.deny, true)
  reset_states()
end

return M
