--- Tool registry for Claude Code MCP integration.
--- We are the MCP server; Claude Code calls tools on us.
local M = {}

M.ERROR_CODES = {
  PARSE_ERROR = -32700,
  INVALID_REQUEST = -32600,
  METHOD_NOT_FOUND = -32601,
  INVALID_PARAMS = -32602,
  INTERNAL_ERROR = -32000,
}

M.tools = {}

---Setup the tools module
function M.setup()
  M.register_all()
end

---Get the complete tool list for MCP tools/list handler
---@return table[] List of tool definitions with name, description, and inputSchema
function M.get_tool_list()
  local tool_list = {}

  for name, tool_data in pairs(M.tools) do
    if tool_data.schema then
      table.insert(tool_list, {
        name = name,
        description = tool_data.schema.description,
        inputSchema = tool_data.schema.inputSchema,
      })
    end
  end

  return tool_list
end

---Register all tools
function M.register_all()
  M.register(require 'claude-inline.tools.get_current_selection')
  M.register(require 'claude-inline.tools.get_latest_selection')
  M.register(require 'claude-inline.tools.open_diff')
end

---Register a tool
---@param tool_module table Tool module with name, handler, schema, and optional requires_coroutine
function M.register(tool_module)
  if not tool_module or not tool_module.name or not tool_module.handler then
    local name = type(tool_module) == 'table' and tool_module.name or 'unknown'
    vim.notify('Error registering tool: Invalid tool module structure for ' .. name, vim.log.levels.ERROR, { title = 'claude-inline Tool Registration' })
    return
  end

  M.tools[tool_module.name] = {
    handler = tool_module.handler,
    schema = tool_module.schema,
    requires_coroutine = tool_module.requires_coroutine,
  }
end

---Handle an invocation of a tool
---@param client table The WebSocket client (needed for blocking tools)
---@param params table Parameters including name and arguments
---@return table Result with either result or error field
function M.handle_invoke(client, params)
  local tool_name = params.name
  local input = params.arguments or {}

  if not M.tools[tool_name] then
    return {
      error = {
        code = M.ERROR_CODES.METHOD_NOT_FOUND,
        message = 'Tool not found: ' .. tool_name,
      },
    }
  end

  local tool_data = M.tools[tool_name]

  local pcall_results
  if tool_data.requires_coroutine then
    -- Wrap in coroutine for blocking behavior
    local co = coroutine.create(function()
      return tool_data.handler(input)
    end)

    local success, result = coroutine.resume(co)

    if coroutine.status(co) == 'suspended' then
      -- The coroutine yielded - tool is blocking, will respond later
      return { _deferred = true, coroutine = co, client = client, params = params }
    end

    pcall_results = { success, result }
  else
    pcall_results = { pcall(tool_data.handler, input) }
  end

  local pcall_success = pcall_results[1]
  local handler_return_val1 = pcall_results[2]
  local handler_return_val2 = pcall_results[3]

  if not pcall_success then
    -- Handler raised an error
    local err_code = M.ERROR_CODES.INTERNAL_ERROR
    local err_msg = 'Tool execution failed'
    local err_data = tostring(handler_return_val1)

    if type(handler_return_val1) == 'table' and handler_return_val1.code and handler_return_val1.message then
      err_code = handler_return_val1.code
      err_msg = handler_return_val1.message
      err_data = handler_return_val1.data
    elseif type(handler_return_val1) == 'string' then
      err_msg = handler_return_val1
    end

    return { error = { code = err_code, message = err_msg, data = err_data } }
  end

  -- Check for (false, error) return pattern
  if handler_return_val1 == false then
    local err_val = handler_return_val2
    local err_code = M.ERROR_CODES.INTERNAL_ERROR
    local err_msg = 'Tool reported an error'
    local err_data = tostring(err_val)

    if type(err_val) == 'table' and err_val.code and err_val.message then
      err_code = err_val.code
      err_msg = err_val.message
      err_data = err_val.data
    elseif type(err_val) == 'string' then
      err_msg = err_val
    end

    return { error = { code = err_code, message = err_msg, data = err_data } }
  end

  -- Success: handler_return_val1 is the result
  return { result = handler_return_val1 }
end

return M
