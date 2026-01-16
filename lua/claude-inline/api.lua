--- API module for Claude Code inline editing.
--- Sends prompts to Claude via the terminal and lets Claude call openDiff.
local M = {}

local state = require 'claude-inline.state'

---Build the full prompt with selection context
---@param user_input string The user's request
---@return string prompt The full prompt to send to Claude
local function build_prompt(user_input)
  local selected_text = state.selected_text or ''

  if selected_text == '' then
    return user_input
  end

  -- Get the file path for context
  local bufnr = state.main_bufnr
  local file_path = ''
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    file_path = vim.api.nvim_buf_get_name(bufnr)
  end

  -- Build prompt that instructs Claude to use openDiff
  local prompt = user_input

  -- Add file context if available
  if file_path ~= '' then
    prompt = prompt .. ' in ' .. file_path
  end

  -- Reference the selection - Claude Code knows about @selection via MCP
  prompt = prompt .. ' @selection'

  return prompt
end

---Get response from Claude via terminal
---Shows floating prompt, sends to Claude terminal on submit
function M.get_response()
  -- Lazy require to avoid circular dependency
  local claude_inline = require 'claude-inline'

  -- Ensure terminal is running (this auto-starts server if needed)
  if not claude_inline.is_terminal_open() then
    claude_inline.open_terminal()
    -- Give Claude a moment to start
    vim.defer_fn(function()
      M._show_prompt()
    end, 500)
    return
  end

  M._show_prompt()
end

---Show the floating input prompt
function M._show_prompt()
  vim.ui.input({ prompt = 'Claude:' }, function(input)
    if not input or input == '' then
      return
    end

    local claude_inline = require 'claude-inline'
    local terminal = require 'claude-inline.terminal'

    -- Ensure terminal is ready
    if not terminal.get_jobid() then
      vim.notify('Claude terminal not ready', vim.log.levels.ERROR)
      return
    end

    -- Build and send the prompt
    local prompt = build_prompt(input)
    local success = terminal.send_prompt(prompt)

    if not success then
      vim.notify('Failed to send prompt to Claude', vim.log.levels.ERROR)
      return
    end

    -- Focus the terminal so user can see Claude's response
    claude_inline.open_terminal()
  end)
end

---Accept the current diff (legacy - diff.lua handles this now via :w)
function M.accept_api_response()
  vim.notify('Use :w in the diff buffer to accept changes', vim.log.levels.INFO)
end

---Reject the current diff (legacy - diff.lua handles this now via closing buffer)
function M.reject_api_response()
  vim.notify('Close the diff buffer to reject changes', vim.log.levels.INFO)
end

return M
