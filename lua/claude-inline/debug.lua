--- Debug utilities for claude-inline.nvim
--- Logs messages to a file for inspection
local M = {}

M._state = {
  enabled = false,
  log_file = nil,
}

--- Enable debug logging
---@param path? string Log file path (default: /tmp/claude-inline-debug.log)
function M.enable(path)
  M._state.enabled = true
  M._state.log_file = path or '/tmp/claude-inline-debug.log'

  -- Clear log file
  local f = io.open(M._state.log_file, 'w')
  if f then
    f:write '=== Claude Inline Debug Log ===\n'
    f:write('Started: ' .. os.date() .. '\n\n')
    f:close()
  end

  vim.notify('Debug logging enabled: ' .. M._state.log_file, vim.log.levels.INFO)
end

--- Disable debug logging
function M.disable()
  M._state.enabled = false
  vim.notify('Debug logging disabled', vim.log.levels.INFO)
end

--- Log a message
---@param category string Category (e.g., 'msg', 'event', 'ui')
---@param data any Data to log
function M.log(category, data)
  if not M._state.enabled then
    return
  end

  local f = io.open(M._state.log_file, 'a')
  if not f then
    return
  end

  local timestamp = os.date '%H:%M:%S'
  local str

  if type(data) == 'table' then
    local ok, json = pcall(vim.json.encode, data)
    str = ok and json or vim.inspect(data)
  else
    str = tostring(data)
  end

  f:write(string.format('[%s] [%s] %s\n', timestamp, category, str))
  f:close()
end

--- Log incoming message with type analysis
---@param msg table The message from Claude CLI
function M.log_message(msg)
  if not M._state.enabled then
    return
  end

  local msg_type = msg.type or 'unknown'

  if msg_type == 'stream_event' then
    local event = msg.event or {}
    local event_type = event.type or 'unknown'

    if event_type == 'content_block_start' then
      local block = event.content_block or {}
      local extra = ''
      if block.type == 'tool_use' then
        extra = string.format(' name=%s id=%s', block.name or '?', block.id or '?')
      end
      M.log('stream', string.format('content_block_start: type=%s index=%s%s', block.type or '?', event.index or '?', extra))
    elseif event_type == 'content_block_delta' then
      local delta = event.delta or {}
      local preview = ''
      if delta.thinking then
        preview = string.sub(delta.thinking, 1, 50):gsub('\n', '\\n')
      elseif delta.text then
        preview = string.sub(delta.text, 1, 50):gsub('\n', '\\n')
      elseif delta.partial_json then
        preview = string.sub(delta.partial_json, 1, 50):gsub('\n', '\\n')
      end
      M.log('stream', string.format('content_block_delta: type=%s preview="%s"', delta.type or '?', preview))
    elseif event_type == 'content_block_stop' then
      M.log('stream', string.format('content_block_stop: index=%s', event.index or '?'))
    else
      M.log('stream', string.format('event: %s', event_type))
    end
  elseif msg_type == 'assistant' then
    local content = msg.message and msg.message.content or {}
    local types = {}
    for _, block in ipairs(content) do
      local block_info = block.type or '?'
      -- Add extra info for tool_use blocks
      if block.type == 'tool_use' then
        block_info = string.format('tool_use(%s)', block.name or '?')
      end
      table.insert(types, block_info)
    end
    M.log('msg', string.format('assistant: content_types=[%s]', table.concat(types, ', ')))
  elseif msg_type == 'user' then
    -- Log user messages (which contain tool_result blocks)
    local content = msg.message and msg.message.content or {}
    local types = {}
    for _, block in ipairs(content) do
      local block_info = block.type or '?'
      if block.type == 'tool_result' then
        block_info = string.format('tool_result(%s%s)', block.tool_use_id or '?', block.is_error and ',error' or '')
      end
      table.insert(types, block_info)
    end
    M.log('msg', string.format('user: content_types=[%s]', table.concat(types, ', ')))
  elseif msg_type == 'result' then
    M.log('msg', string.format('result: subtype=%s', msg.subtype or '?'))
  elseif msg_type == 'system' then
    M.log('msg', string.format('system: subtype=%s', msg.subtype or '?'))
  else
    M.log('msg', string.format('unknown type: %s', msg_type))
  end
end

return M
