--- Shared formatting utilities for tool display
--- Used by tool_use.lua and tool_result.lua

local M = {}

local MAX_PARAM_LEN = 60

-- Maps tool name to the input field that best identifies what it operates on
---@type table<string, string>
local KEY_PARAM_FIELDS = {
  Bash = 'command',
  Read = 'file_path',
  Grep = 'pattern',
  Glob = 'pattern',
  Edit = 'file_path',
  Write = 'file_path',
  Task = 'description',
  WebSearch = 'query',
  WebFetch = 'url',
}

---@param tool_name string
---@param input table|nil
---@return string|nil
local function get_key_param(tool_name, input)
  if not input then
    return nil
  end

  local field = KEY_PARAM_FIELDS[tool_name]
  if field and input[field] then
    return input[field]
  end

  -- Unknown tool: use first string value as reasonable fallback
  for _, v in pairs(input) do
    if type(v) == 'string' then
      return v
    end
  end
  return nil
end

--- Format a tool invocation as a single line: ToolName(key_param)
---@param tool_name string
---@param input table|nil
---@return string
function M.tool_line(tool_name, input)
  local key_param = get_key_param(tool_name, input)
  if not key_param then
    return tool_name
  end

  -- nvim_buf_set_lines rejects embedded newlines
  key_param = key_param:gsub('\n', ' ')
  if #key_param > MAX_PARAM_LEN then
    key_param = key_param:sub(1, MAX_PARAM_LEN - 3) .. '...'
  end
  return string.format('%s(%s)', tool_name, key_param)
end

---@param metadata table|nil tool_use_result from Claude CLI
---@return string suffix to append after status icon
function M.metadata_suffix(metadata)
  if not metadata then
    return ''
  end

  -- Read tool: show line count
  if metadata.file and metadata.file.numLines then
    return string.format(' %d lines', metadata.file.numLines)
  end

  -- Bash tool: show exit code only on failure
  if metadata.exitCode and metadata.exitCode ~= 0 then
    return string.format(' exit %d', metadata.exitCode)
  end

  -- Task (sub-agent): show duration and tool count
  if metadata.totalDurationMs then
    local secs = metadata.totalDurationMs / 1000
    return string.format(' %.1fs, %d tools', secs, metadata.totalToolUseCount or 0)
  end

  return ''
end

return M
