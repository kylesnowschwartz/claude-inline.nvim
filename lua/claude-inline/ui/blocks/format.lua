--- Shared formatting utilities for tool display
--- Used by tool_use.lua and tool_result.lua

local M = {}

-- Maps tool name to the input field that best identifies what it operates on
---@type table<string, string>
local KEY_PARAM_FIELDS = {
  Bash = "command",
  Read = "file_path",
  Grep = "pattern",
  Glob = "pattern",
  Edit = "file_path",
  Write = "file_path",
  Task = "description",
  WebSearch = "query",
  WebFetch = "url",
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
    if type(v) == "string" then
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
  key_param = key_param:gsub("\n", " ")
  return string.format("%s(%s)", tool_name, key_param)
end

---@param metadata table|nil tool_use_result from Claude CLI
---@return string suffix to append after status icon
function M.metadata_suffix(metadata)
  if not metadata then
    return ""
  end

  local suffix = ""

  -- Read tool: show line count
  if metadata.file and metadata.file.numLines then
    suffix = string.format(" %d lines", metadata.file.numLines)
  -- Bash tool: show exit code only on failure
  elseif metadata.exitCode and metadata.exitCode ~= 0 then
    suffix = string.format(" exit %d", metadata.exitCode)
  -- Task (sub-agent): show duration and tool count
  elseif metadata.totalDurationMs then
    local secs = metadata.totalDurationMs / 1000
    suffix = string.format(" %.1fs, %d tools", secs, metadata.totalToolUseCount or 0)
  -- Glob/file search: show file count
  elseif metadata.numFiles then
    suffix = string.format(" %d files", metadata.numFiles)
  -- Grep/search: show match count
  elseif metadata.numMatches then
    suffix = string.format(" %d matches", metadata.numMatches)
  end

  -- Individual tool duration (Task uses totalDurationMs above, skip double-counting)
  if metadata.durationMs and not metadata.totalDurationMs then
    local ms = metadata.durationMs
    if ms >= 1000 then
      suffix = suffix .. string.format(" %.1fs", ms / 1000)
    else
      suffix = suffix .. string.format(" %dms", ms)
    end
  end

  -- Truncation appends to any tool's suffix
  if metadata.truncated then
    suffix = suffix .. " (truncated)"
  end

  return suffix
end

return M
