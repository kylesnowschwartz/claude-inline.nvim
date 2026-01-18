--- Message block component for claude-inline.nvim
--- Handles user and assistant message display

local state = require 'claude-inline.ui.state'
local buffer = require 'claude-inline.ui.buffer'
local fold = require 'claude-inline.ui.fold'

local M = {}

--- Create an extmark to track a message block boundary
---@param role 'user'|'assistant'
---@param start_line number 0-indexed line where message starts
---@return number extmark_id
local function create_extmark(role, start_line)
  local mark_id = vim.api.nvim_buf_set_extmark(state.sidebar_buf, state.MESSAGE_NS, start_line, 0, {
    right_gravity = false, -- Stays put when text inserted at this position
  })
  table.insert(state.message_blocks, { id = mark_id, role = role, folded = false })
  return mark_id
end

--- Append a message to the conversation buffer
---@param role string 'user' or 'assistant'
---@param text string
function M.append(role, text)
  -- Close any open message before starting a new one
  M.close_current()

  -- Message header (foldexpr detects these for folding)
  local prefix = role == 'user' and '**You:**' or '**Claude:**'
  local lines = vim.split(prefix .. '\n' .. text .. '\n\n', '\n', { plain = true })
  local start_line

  buffer.with_modifiable(function()
    local line_count = vim.api.nvim_buf_line_count(state.sidebar_buf)
    local last_line = vim.api.nvim_buf_get_lines(state.sidebar_buf, line_count - 1, line_count, false)[1]

    -- If buffer is empty (just one empty line), replace it
    if line_count == 1 and last_line == '' then
      start_line = 0
      vim.api.nvim_buf_set_lines(state.sidebar_buf, 0, 1, false, lines)
    else
      start_line = line_count -- 0-indexed: next line after current content
      vim.api.nvim_buf_set_lines(state.sidebar_buf, -1, -1, false, lines)
    end
  end)

  -- Force vim to re-evaluate foldexpr after buffer content changes
  fold.refresh()

  -- Track that assistant message is still streaming
  state.current_message_open = (role == 'assistant')

  create_extmark(role, start_line)

  -- Collapse previous messages (but not the new one)
  -- Schedule fold closing to ensure foldexpr has evaluated the new content
  if buffer.is_sidebar_open() and #state.message_blocks > 1 then
    -- Capture current block count at scheduling time
    local blocks_to_close = #state.message_blocks - 1
    vim.schedule(function()
      if not buffer.is_sidebar_open() then
        return
      end
      vim.api.nvim_win_call(state.sidebar_win, function()
        -- Close each previous message fold individually (not zM which changes foldlevel)
        for i = 1, blocks_to_close do
          local block = state.message_blocks[i]
          if block then
            local mark = vim.api.nvim_buf_get_extmark_by_id(state.sidebar_buf, state.MESSAGE_NS, block.id, {})
            if mark and #mark > 0 then
              local line = mark[1] + 1
              local line_content = vim.fn.getline(line)
              local foldlevel_before = vim.fn.foldlevel(line)
              local closed_before = vim.fn.foldclosed(line)
              vim.api.nvim_win_set_cursor(state.sidebar_win, { line, 0 })
              vim.cmd 'silent! normal! zc'
              local closed_after = vim.fn.foldclosed(line)
              -- Debug output
              if state.config and state.config.debug then
                local debug = require 'claude-inline.debug'
                debug.log(
                  'FOLD',
                  string.format(
                    'block %d (%s) line %d [%s]: foldlevel=%d, closed %d->%d',
                    i,
                    block.role,
                    line,
                    line_content:sub(1, 20),
                    foldlevel_before,
                    closed_before,
                    closed_after
                  )
                )
              end
              block.folded = true
            end
          end
        end
      end)
    end)
  end

  buffer.scroll_to_bottom()
end

--- Update the last assistant message (for streaming)
---@param text string
function M.update_last(text)
  if not buffer.is_valid() then
    return
  end

  -- Get last assistant block via extmarks
  local last_block = state.message_blocks[#state.message_blocks]
  if not last_block or last_block.role ~= 'assistant' then
    return
  end

  local mark = vim.api.nvim_buf_get_extmark_by_id(state.sidebar_buf, state.MESSAGE_NS, last_block.id, {})
  if not mark or #mark == 0 then
    return
  end

  -- Content starts after header line (mark[1] is 0-indexed row)
  local start_line = mark[1] + 1

  local new_lines = vim.split(text .. '\n', '\n', { plain = true })

  buffer.with_modifiable(function()
    vim.api.nvim_buf_set_lines(state.sidebar_buf, start_line, -1, false, new_lines)
  end)

  buffer.scroll_to_bottom()
end

--- Mark the current message as complete
--- Called when streaming completes or before starting a new message
function M.close_current()
  -- Just mark the message as complete (foldexpr handles fold boundaries)
  state.current_message_open = false
end

return M
