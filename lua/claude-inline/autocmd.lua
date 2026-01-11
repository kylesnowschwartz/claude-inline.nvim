local M = {}
local api = vim.api
local utils = require 'claude-inline.utils'
local state = require 'claude-inline.state'

M.setup = function()
  -- Visual mode entered: show the inline command hint
  api.nvim_create_autocmd('ModeChanged', {
    pattern = 'n:[vV\22]',
    callback = function()
      local ui = require 'claude-inline.ui'
      ui.open_inline_command()
    end,
  })

  -- Visual mode exited: capture selection and broadcast to Claude Code
  api.nvim_create_autocmd('ModeChanged', {
    pattern = '[vV\22]:n',
    callback = function()
      local ui = require 'claude-inline.ui'
      ui.close_inline_command()

      local lines = utils.get_visual_selection()
      local bufnr = api.nvim_get_current_buf()
      local text = table.concat(lines, '\n')

      -- Get selection positions from marks (0-indexed line, 0-indexed character for LSP)
      local start_mark = api.nvim_buf_get_mark(bufnr, '<')
      local end_mark = api.nvim_buf_get_mark(bufnr, '>')

      -- Update state with full selection info
      state.set_selection(text, bufnr, {
        line = start_mark[1] - 1, -- Convert to 0-indexed
        character = start_mark[2],
      }, {
        line = end_mark[1] - 1, -- Convert to 0-indexed
        character = end_mark[2],
      })

      -- Broadcast selection change to Claude Code
      local claude_inline = require 'claude-inline'
      if claude_inline.is_running() then
        local file_path = api.nvim_buf_get_name(bufnr)
        claude_inline.broadcast('selection/changed', {
          text = text,
          filePath = file_path,
          start = { line = start_mark[1] - 1, character = start_mark[2] },
          ['end'] = { line = end_mark[1] - 1, character = end_mark[2] },
        })
      end
    end,
  })

  -- Visual mode cursor movement: update inline command position
  api.nvim_create_autocmd('CursorMoved', {
    callback = function()
      if vim.fn.mode():match '[vV\22]' then
        local ui = require 'claude-inline.ui'
        ui.move_inline_command()
      end
    end,
  })
end

return M
