--- Loading spinner for claude-inline.nvim
--- Shows animated spinner while waiting for Claude response

local uv = vim.uv or vim.loop
local state = require("claude-inline.ui.state")

local M = {}

-- Callbacks to message functions (set by parent module to avoid circular deps)
local append_message_fn = nil
local update_last_message_fn = nil

--- Register message callbacks
---@param append_fn function append_message function
---@param update_fn function update_last_message function
function M.setup_callbacks(append_fn, update_fn)
  append_message_fn = append_fn
  update_last_message_fn = update_fn
end

--- Show loading indicator in sidebar
function M.show()
  if state.loading_timer then
    return
  end

  if not append_message_fn or not update_last_message_fn then
    error("Loading callbacks not registered. Call setup_callbacks first.")
  end

  local config = state.config.ui.loading

  -- Add "Claude:" marker first
  append_message_fn("assistant", "")

  state.spinner_index = 1
  state.loading_timer = uv.new_timer()

  state.loading_timer:start(
    0,
    config.interval,
    vim.schedule_wrap(function()
      if not state.loading_timer then
        return
      end

      local spinner = config.spinner[state.spinner_index]
      local text = spinner .. " " .. config.text
      update_last_message_fn(text)

      state.spinner_index = state.spinner_index % #config.spinner + 1
    end)
  )
end

--- Hide loading indicator and clear spinner text from buffer
function M.hide()
  if state.loading_timer then
    state.loading_timer:stop()
    state.loading_timer:close()
    state.loading_timer = nil

    -- Clear the spinner text, leaving just the assistant header
    if update_last_message_fn then
      update_last_message_fn("")
    end
  end
end

return M
