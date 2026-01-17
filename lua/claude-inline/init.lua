--- claude-inline.nvim - Minimal Claude chat in Neovim
--- Send prompts to Claude CLI with persistent conversation context
local M = {}

local config = require("claude-inline.config")
local client = require("claude-inline.client")
local ui = require("claude-inline.ui")
local selection = require("claude-inline.selection")
local debug = require("claude-inline.debug")

M._state = {
  initialized = false,
  streaming_text = "",
  thinking_text = "",
}

--- Handle incoming messages from Claude CLI
---@param msg table
local function handle_message(msg)
  -- Debug logging
  debug.log_message(msg)

  local msg_type = msg.type

  if msg_type == "system" then
    -- Ignore system/hook messages
    return
  end

  -- Handle granular streaming events (with --include-partial-messages)
  if msg_type == "stream_event" then
    local event = msg.event
    if not event then
      return
    end

    if event.type == "content_block_start" then
      local block = event.content_block or {}

      if block.type == "thinking" then
        -- Starting a thinking block
        ui.hide_loading()
        ui.show_thinking()
      end
    elseif event.type == "content_block_delta" then
      local delta = event.delta or {}

      if delta.type == "thinking_delta" then
        M._state.thinking_text = M._state.thinking_text .. (delta.thinking or "")
        ui.update_thinking(M._state.thinking_text)
      elseif delta.type == "text_delta" then
        -- First text after thinking? Collapse thinking section
        if M._state.thinking_text ~= "" and M._state.streaming_text == "" then
          ui.collapse_thinking()
        end
        ui.hide_loading()
        M._state.streaming_text = M._state.streaming_text .. (delta.text or "")
        ui.update_last_message(M._state.streaming_text)
      end
    end
    return
  end

  if msg_type == "assistant" then
    -- Stop spinner immediately when we get content
    ui.hide_loading()

    -- If we already have streamed content via stream_events, skip
    -- The assistant message is just a summary of what we already displayed
    if M._state.streaming_text ~= "" then
      return
    end

    -- Fallback: if no stream_events came, use assistant message content
    local content = msg.message and msg.message.content
    if content then
      for _, block in ipairs(content) do
        if block.type == "text" then
          M._state.streaming_text = M._state.streaming_text .. (block.text or "")
          ui.update_last_message(M._state.streaming_text)
        end
      end
    end
    return
  end

  if msg_type == "result" then
    -- Final result
    ui.hide_loading()

    local result_text = msg.result
    if result_text and result_text ~= "" then
      -- If we have streamed content, it's already shown
      -- If not, show the result
      if M._state.streaming_text == "" then
        ui.update_last_message(result_text)
      end
    end

    -- Close the current message fold (add closing marker)
    ui.close_current_message()

    M._state.streaming_text = ""
    M._state.thinking_text = ""
    return
  end
end

--- Handle errors from Claude CLI
---@param err string
local function handle_error(err)
  ui.hide_loading()
  vim.notify("Claude error: " .. err, vim.log.levels.ERROR)
end

--- Send a prompt to Claude
---@param prompt string
function M.send(prompt)
  if not M._state.initialized then
    vim.notify("Claude Inline not initialized. Call setup() first.", vim.log.levels.ERROR)
    return
  end

  -- Make sure sidebar is visible
  ui.show_sidebar()

  -- Add user message to chat
  ui.append_message("user", prompt)

  -- Reset streaming state
  M._state.streaming_text = ""
  M._state.thinking_text = ""

  -- Start client if needed
  if not client.is_running() then
    local ok = client.start(handle_message, handle_error)
    if not ok then
      vim.notify("Failed to start Claude process", vim.log.levels.ERROR)
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

--- Show input prompt with visual selection context
function M.prompt_with_selection()
  -- Capture selection while still in visual mode
  local sel = selection.capture()

  -- Now exit visual mode
  vim.cmd("normal! " .. vim.api.nvim_replace_termcodes("<Esc>", true, false, true))

  if not sel then
    vim.notify("No text selected", vim.log.levels.WARN)
    return
  end

  local context = selection.format_context(sel)

  ui.show_input(function(input)
    if input then
      M.send(context .. input)
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
  M._state.streaming_text = ""
  M._state.thinking_text = ""
end

--- Setup the plugin
---@param opts? table User configuration
function M.setup(opts)
  local cfg = config.setup(opts)

  client.setup(cfg)
  ui.setup(cfg)

  -- Enable debug logging if configured
  if cfg.debug then
    debug.enable()
  end

  M._state.initialized = true

  -- Create user commands
  vim.api.nvim_create_user_command("ClaudeInlineSend", function()
    M.prompt()
  end, { desc = "Send prompt to Claude" })

  vim.api.nvim_create_user_command("ClaudeInlineToggle", function()
    M.toggle()
  end, { desc = "Toggle Claude chat sidebar" })

  vim.api.nvim_create_user_command("ClaudeInlineClear", function()
    M.clear()
  end, { desc = "Clear Claude conversation" })

  vim.api.nvim_create_user_command("ClaudeInlineDebug", function(cmd)
    if cmd.args == "on" then
      debug.enable()
    elseif cmd.args == "off" then
      debug.disable()
    else
      vim.notify("Usage: ClaudeInlineDebug on|off", vim.log.levels.INFO)
    end
  end, { nargs = "?", desc = "Toggle debug logging" })

  vim.api.nvim_create_user_command("ClaudeInlineFoldAll", function()
    ui.fold_all()
  end, { desc = "Collapse all Claude messages" })

  vim.api.nvim_create_user_command("ClaudeInlineUnfoldAll", function()
    ui.unfold_all()
  end, { desc = "Expand all Claude messages" })

  -- Setup keymaps
  local keymaps = cfg.keymaps
  if keymaps.send then
    vim.keymap.set("n", keymaps.send, M.prompt, { desc = "Send to Claude" })
    vim.keymap.set("v", keymaps.send, M.prompt_with_selection, { desc = "Send selection to Claude" })
  end
  if keymaps.toggle then
    vim.keymap.set("n", keymaps.toggle, M.toggle, { desc = "Toggle Claude sidebar" })
  end
  if keymaps.clear then
    vim.keymap.set("n", keymaps.clear, M.clear, { desc = "Clear Claude conversation" })
  end

  -- Cleanup on Neovim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      client.stop()
      ui.cleanup()
    end,
  })
end

-- Expose debug module for direct access
M.debug = debug

return M
