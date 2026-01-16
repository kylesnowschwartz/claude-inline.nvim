--- claude-inline.nvim - Minimal Claude chat in Neovim
--- Send prompts to Claude CLI with persistent conversation context
local M = {}

local config = require 'claude-inline.config'
local client = require 'claude-inline.client'
local ui = require 'claude-inline.ui'

M._state = {
  initialized = false,
  streaming_text = '',
}

--- Handle incoming messages from Claude CLI
---@param msg table
local function handle_message(msg)
  local msg_type = msg.type

  if msg_type == 'system' then
    -- Ignore system/hook messages
    return
  end

  if msg_type == 'assistant' then
    -- Stop spinner immediately when we get content
    ui.hide_loading()

    local content = msg.message and msg.message.content
    if content then
      for _, block in ipairs(content) do
        if block.type == 'text' then
          M._state.streaming_text = M._state.streaming_text .. (block.text or '')
          ui.update_last_message(M._state.streaming_text)
        end
      end
    end
    return
  end

  if msg_type == 'result' then
    -- Final result
    ui.hide_loading()

    local result_text = msg.result
    if result_text and result_text ~= '' then
      -- If we have streamed content, it's already shown
      -- If not, show the result
      if M._state.streaming_text == '' then
        ui.update_last_message(result_text)
      end
    end

    M._state.streaming_text = ''
    return
  end
end

--- Handle errors from Claude CLI
---@param err string
local function handle_error(err)
  ui.hide_loading()
  vim.notify('Claude error: ' .. err, vim.log.levels.ERROR)
end

--- Send a prompt to Claude
---@param prompt string
function M.send(prompt)
  if not M._state.initialized then
    vim.notify('Claude Inline not initialized. Call setup() first.', vim.log.levels.ERROR)
    return
  end

  -- Make sure sidebar is visible
  ui.show_sidebar()

  -- Add user message to chat
  ui.append_message('user', prompt)

  -- Reset streaming state
  M._state.streaming_text = ''

  -- Start client if needed
  if not client.is_running() then
    local ok = client.start(handle_message, handle_error)
    if not ok then
      vim.notify('Failed to start Claude process', vim.log.levels.ERROR)
      return
    end
  end

  -- Show loading and send
  ui.show_loading()
  client.send(prompt)
end

--- Show input prompt and send on submit
function M.prompt()
  ui.show_input(function(input)
    if input then
      M.send(input)
    end
  end)
end

--- Toggle sidebar visibility
function M.toggle()
  ui.toggle_sidebar()
end

--- Clear conversation and restart Claude process
function M.clear()
  ui.clear()
  client.stop()
  M._state.streaming_text = ''
end

--- Setup the plugin
---@param opts? table User configuration
function M.setup(opts)
  local cfg = config.setup(opts)

  client.setup(cfg)
  ui.setup(cfg)

  M._state.initialized = true

  -- Create user commands
  vim.api.nvim_create_user_command('ClaudeInlineSend', function()
    M.prompt()
  end, { desc = 'Send prompt to Claude' })

  vim.api.nvim_create_user_command('ClaudeInlineToggle', function()
    M.toggle()
  end, { desc = 'Toggle Claude chat sidebar' })

  vim.api.nvim_create_user_command('ClaudeInlineClear', function()
    M.clear()
  end, { desc = 'Clear Claude conversation' })

  -- Setup keymaps
  local keymaps = cfg.keymaps
  if keymaps.send then
    vim.keymap.set('n', keymaps.send, M.prompt, { desc = 'Send to Claude' })
  end
  if keymaps.toggle then
    vim.keymap.set('n', keymaps.toggle, M.toggle, { desc = 'Toggle Claude sidebar' })
  end
  if keymaps.clear then
    vim.keymap.set('n', keymaps.clear, M.clear, { desc = 'Clear Claude conversation' })
  end

  -- Cleanup on Neovim exit
  vim.api.nvim_create_autocmd('VimLeavePre', {
    callback = function()
      client.stop()
      ui.cleanup()
    end,
  })
end

return M
