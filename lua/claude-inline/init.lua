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
}

--- Strip XML noise tags injected by Claude CLI as system metadata.
--- These tags appear in message content but add no value in the sidebar.
---@param text string
---@return string
local function sanitize_text(text)
  local noise_tags = { "system-reminder", "local-command-caveat" }
  for _, tag in ipairs(noise_tags) do
    local open = "<" .. tag .. ">"
    local close = "</" .. tag .. ">"
    while true do
      local i = text:find(open, 1, true)
      if not i then
        break
      end
      local j = text:find(close, i, true)
      if not j then
        break
      end
      text = text:sub(1, i - 1) .. text:sub(j + #close)
    end
  end
  -- Collapse runs of blank lines left behind by removed tags
  text = text:gsub("\n\n\n+", "\n\n")
  return vim.trim(text)
end

--- Handle incoming messages from Claude CLI
--- Processes settled messages only (no streaming deltas).
--- Each assistant JSONL entry contains exactly ONE content block.
---@param msg table
local function handle_message(msg)
  debug.log_message(msg)

  local msg_type = msg.type

  -- System messages: hooks, init metadata. Ignore all of them.
  if msg_type == "system" then
    return
  end

  -- Stream events: we don't use --include-partial-messages, so these
  -- shouldn't arrive. Ignore defensively.
  if msg_type == "stream_event" then
    return
  end

  -- Assistant messages: each entry has one content block (thinking, text, or tool_use)
  if msg_type == "assistant" then
    local content = msg.message and msg.message.content
    if not content or type(content) ~= "table" then
      return
    end

    for _, block in ipairs(content) do
      if block.type == "text" and block.text and block.text ~= "" then
        local clean = sanitize_text(block.text)
        if clean ~= "" then
          ui.hide_loading()
          ui.append_text(clean)
        end
      elseif block.type == "thinking" and block.thinking and block.thinking ~= "" then
        ui.hide_loading()
        -- Format as foldable section: > **Thinking** header + > prefixed lines
        local parts = { "> **Thinking**" }
        for _, line in ipairs(vim.split(block.thinking, "\n", { plain = true })) do
          parts[#parts + 1] = "> " .. line
        end
        ui.append_text(table.concat(parts, "\n"))
      elseif block.type == "tool_use" then
        ui.hide_loading()
        ui.show_tool_use(block.id, block.name, block.input, msg.parent_tool_use_id)
      end
    end
    return
  end

  -- User messages: tool results flowing back to Claude
  if msg_type == "user" then
    local metadata = msg.tool_use_result
    local content = msg.message and msg.message.content
    if type(content) == "table" then
      for _, block in ipairs(content) do
        if block.type == "tool_result" then
          ui.show_tool_result(block.tool_use_id, block.content or "", block.is_error, metadata)
        end
      end
    end
    return
  end

  -- Result: conversation turn complete
  if msg_type == "result" then
    ui.hide_loading()
    ui.close_current_message()
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

-- Expose internals for integration testing
M._test = {
  handle_message = handle_message,
}

return M
