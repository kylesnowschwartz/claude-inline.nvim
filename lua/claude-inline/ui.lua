--- UI module for Claude Code inline editing.
--- Provides the visual selection hint during visual mode.
--- The old floating prompt/accept-reject UI has been removed - Claude terminal handles interactions.
local M = {}

local api = vim.api
local config = require 'claude-inline.config'

local bufnr, win_id

---Open the inline command hint during visual mode
function M.open_inline_command()
  if win_id and api.nvim_win_is_valid(win_id) then
    return
  end

  bufnr = api.nvim_create_buf(false, true)
  local toggle_key = config.mappings.toggle_terminal or '<leader>cc'
  api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'Claude (' .. toggle_key .. ')' })

  win_id = api.nvim_open_win(bufnr, false, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = math.max(12, #toggle_key + 10),
    height = 1,
    style = 'minimal',
  })
end

---Move the inline command hint to follow cursor
function M.move_inline_command()
  if not (win_id and api.nvim_win_is_valid(win_id)) then
    return
  end

  api.nvim_win_set_config(win_id, {
    relative = 'cursor',
    row = 1,
    col = 0,
  })
end

---Close the inline command hint
function M.close_inline_command()
  if win_id and api.nvim_win_is_valid(win_id) then
    api.nvim_win_close(win_id, true)
  end
  if bufnr and api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_delete(bufnr, { force = true })
  end
  win_id, bufnr = nil, nil
end

function M.setup()
  -- No setup needed - just providing visual hints
end

return M
