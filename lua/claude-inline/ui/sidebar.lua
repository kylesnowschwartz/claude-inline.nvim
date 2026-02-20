--- Sidebar window management for claude-inline.nvim
--- Creates and manages the sidebar split window

local state = require("claude-inline.ui.state")
local buffer = require("claude-inline.ui.buffer")

local M = {}

--- Define highlight groups for message display
--- Uses default=true so colorschemes can override, and links to standard
--- groups so colors automatically match the user's theme.
local function define_highlights()
  local set = vim.api.nvim_set_hl

  -- Signs: inherit from semantic groups the colorscheme already defines
  set(0, "CISignUser", { default = true, link = "Function" })
  set(0, "CISignAssistant", { default = true, link = "Keyword" })

  -- Header backgrounds: subtle differentiation via existing UI groups
  set(0, "CIUserHeader", { default = true, link = "CursorLine" })
  set(0, "CIAssistantHeader", { default = true, link = "ColorColumn" })

  -- Right-aligned metadata (tool count, duration)
  set(0, "CISummary", { default = true, link = "Comment" })
end

-- Define once on load. default=true means colorscheme wins if it
-- defines these groups, so no ColorScheme autocmd needed.
define_highlights()

--- Check if sidebar is open
---@return boolean
function M.is_open()
  return state.sidebar_win ~= nil and vim.api.nvim_win_is_valid(state.sidebar_win)
end

--- Show the sidebar
function M.show()
  -- Sidebar already visible, nothing to do
  if M.is_open() then
    return
  end

  -- Save current window to restore focus after creating sidebar
  local original_win = vim.api.nvim_get_current_win()

  local config = state.config.ui.sidebar

  -- Create sidebar buffer if needed
  if not buffer.is_valid() then
    state.sidebar_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.sidebar_buf })
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.sidebar_buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = state.sidebar_buf })
    vim.api.nvim_buf_set_name(state.sidebar_buf, "Claude Chat")
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = state.sidebar_buf })

    -- Enable treesitter highlighting (doesn't auto-activate on scratch buffers)
    pcall(vim.treesitter.start, state.sidebar_buf, "markdown")
  end

  -- Calculate width
  local width = math.floor(vim.o.columns * config.width)

  -- Create split (this focuses the new window)
  local cmd = config.position == "left" and "topleft" or "botright"
  vim.cmd(cmd .. " vertical " .. width .. "split")

  state.sidebar_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.sidebar_win, state.sidebar_buf)

  -- Window options
  vim.api.nvim_set_option_value("wrap", true, { win = state.sidebar_win })
  vim.api.nvim_set_option_value("linebreak", true, { win = state.sidebar_win })
  vim.api.nvim_set_option_value("number", false, { win = state.sidebar_win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = state.sidebar_win })
  vim.api.nvim_set_option_value("signcolumn", "yes:1", { win = state.sidebar_win })
  -- Folding: use manual initially, switch to expr after content is added
  -- This prevents vim from caching foldlevel=0 for empty buffer lines
  vim.api.nvim_set_option_value("foldmethod", "manual", { win = state.sidebar_win })
  vim.api.nvim_set_option_value("foldexpr", "v:lua.require'claude-inline.ui'.foldexpr()", { win = state.sidebar_win })
  vim.api.nvim_set_option_value("foldtext", "v:lua.require'claude-inline.ui'.foldtext()", { win = state.sidebar_win })
  vim.api.nvim_set_option_value("foldenable", true, { win = state.sidebar_win })
  vim.api.nvim_set_option_value("foldlevel", 99, { win = state.sidebar_win }) -- Start open, collapse manually
  -- Clean fold display: spaces instead of dots after foldtext
  vim.api.nvim_set_option_value("fillchars", "fold: ", { win = state.sidebar_win })

  -- Setup autocmd to track window close
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.sidebar_win),
    once = true,
    callback = function()
      state.sidebar_win = nil
    end,
  })

  -- Restore focus to original window - sidebar is for display, not editing
  vim.api.nvim_set_current_win(original_win)
end

--- Hide the sidebar
function M.hide()
  if M.is_open() then
    vim.api.nvim_win_close(state.sidebar_win, true)
    state.sidebar_win = nil
  end
end

--- Toggle the sidebar
function M.toggle()
  if M.is_open() then
    M.hide()
  else
    M.show()
  end
end

return M
