--- End-to-end smoke test for claude-inline.nvim
--- Tests the complete flow: setup -> server start -> selection tracking -> MCP tools
---
--- Unlike unit tests, E2E tests run with the real plugin (not mocked).
--- They verify integration between components.

-- E2E tests don't use busted_setup since they need real Neovim APIs
-- This test runs via: nvim --headless -u NONE -c "set runtimepath+=." -l tests/e2e/smoke_test_spec.lua

local passed = 0
local failed = 0

local function expect(value)
  return {
    to_be = function(expected)
      assert(value == expected, 'Expected ' .. tostring(expected) .. ', got ' .. tostring(value))
    end,
    to_be_nil = function()
      assert(value == nil, 'Expected nil, got ' .. tostring(value))
    end,
    to_be_true = function()
      assert(value == true, 'Expected true, got ' .. tostring(value))
    end,
    to_be_false = function()
      assert(value == false, 'Expected false, got ' .. tostring(value))
    end,
    to_be_table = function()
      assert(type(value) == 'table', 'Expected table, got ' .. type(value))
    end,
    not_to_be_nil = function()
      assert(value ~= nil, 'Expected non-nil value')
    end,
    to_be_at_least = function(expected)
      assert(value >= expected, 'Expected at least ' .. tostring(expected) .. ', got ' .. tostring(value))
    end,
  }
end

local function it(description, fn)
  local ok, err = pcall(fn)
  if ok then
    print('[PASS] ' .. description)
    passed = passed + 1
  else
    print('[FAIL] ' .. description)
    print('       ' .. tostring(err))
    failed = failed + 1
  end
end

local function describe(name, fn)
  print ''
  print('=== ' .. name .. ' ===')
  fn()
end

-- Track server for cleanup
local claude_inline

describe('Plugin Loading', function()
  it('should load the plugin without error', function()
    local ok, result = pcall(require, 'claude-inline')
    expect(ok).to_be_true()
    expect(result).to_be_table()
    claude_inline = result
  end)

  it('should have setup function', function()
    expect(type(claude_inline.setup)).to_be 'function'
  end)

  it('should have server control functions', function()
    expect(type(claude_inline.start)).to_be 'function'
    expect(type(claude_inline.stop)).to_be 'function'
    expect(type(claude_inline.is_running)).to_be 'function'
  end)

  it('should have terminal control functions', function()
    expect(type(claude_inline.toggle_terminal)).to_be 'function'
    expect(type(claude_inline.open_terminal)).to_be 'function'
    expect(type(claude_inline.close_terminal)).to_be 'function'
  end)
end)

describe('Plugin Setup', function()
  it('should run setup without error', function()
    local ok, err = pcall(claude_inline.setup, {})
    expect(ok).to_be_true()
  end)
end)

describe('WebSocket Server Lifecycle', function()
  it('should start the server successfully', function()
    local ok, err = claude_inline.start()
    expect(ok).to_be_true()
  end)

  it('should report running after start', function()
    expect(claude_inline.is_running()).to_be_true()
  end)

  it('should return valid status with port', function()
    local status = claude_inline.get_status()
    expect(status).to_be_table()
    expect(status.running).to_be_true()
    expect(status.port).not_to_be_nil()
  end)
end)

describe('State Module', function()
  it('should track selection state', function()
    local state = require 'claude-inline.state'
    state.set_selection('test code', 1, { line = 0, character = 0 }, { line = 0, character = 8 })
    expect(state.selected_text).to_be 'test code'
    expect(state.main_bufnr).to_be(1)
    expect(state.selection_start.line).to_be(0)
    expect(state.selection_end.character).to_be(8)
  end)

  it('should clear selection state', function()
    local state = require 'claude-inline.state'
    state.clear_selection()
    expect(state.selected_text).to_be ''
    expect(state.main_bufnr).to_be_nil()
  end)
end)

describe('MCP Tools Module', function()
  local tools

  it('should load tools module', function()
    local ok, result = pcall(require, 'claude-inline.tools')
    expect(ok).to_be_true()
    tools = result
  end)

  it('should return at least 3 registered tools', function()
    local tool_list = tools.get_tool_list()
    expect(#tool_list).to_be_at_least(3)
  end)

  it('should have getCurrentSelection tool', function()
    local tool_list = tools.get_tool_list()
    local found = false
    for _, tool in ipairs(tool_list) do
      if tool.name == 'getCurrentSelection' then
        found = true
        break
      end
    end
    expect(found).to_be_true()
  end)

  it('should have getLatestSelection tool', function()
    local tool_list = tools.get_tool_list()
    local found = false
    for _, tool in ipairs(tool_list) do
      if tool.name == 'getLatestSelection' then
        found = true
        break
      end
    end
    expect(found).to_be_true()
  end)

  it('should have openDiff tool', function()
    local tool_list = tools.get_tool_list()
    local found = false
    for _, tool in ipairs(tool_list) do
      if tool.name == 'openDiff' then
        found = true
        break
      end
    end
    expect(found).to_be_true()
  end)
end)

describe('Tool Invocation', function()
  local tools

  it('should execute getCurrentSelection and return MCP format', function()
    tools = require 'claude-inline.tools'
    local result = tools.handle_invoke({}, { name = 'getCurrentSelection', arguments = {} })
    expect(result).to_be_table()
    expect(result.result).to_be_table()
    expect(result.result.content).to_be_table()
    expect(result.result.content[1].type).to_be 'text'
  end)

  it('should execute getLatestSelection and return MCP format', function()
    local result = tools.handle_invoke({}, { name = 'getLatestSelection', arguments = {} })
    expect(result).to_be_table()
    expect(result.result).to_be_table()
    expect(result.result.content).to_be_table()
    expect(result.result.content[1].type).to_be 'text'
  end)

  it('should return error for unknown tool', function()
    local result = tools.handle_invoke({}, { name = 'nonExistentTool', arguments = {} })
    expect(result).to_be_table()
    expect(result.error).to_be_table()
    expect(result.error.code).to_be(-32601) -- METHOD_NOT_FOUND
  end)
end)

describe('Broadcast', function()
  it('should broadcast without error when server running', function()
    local ok, err = pcall(claude_inline.broadcast, 'test/event', { test = true })
    expect(ok).to_be_true()
  end)
end)

describe('Server Shutdown', function()
  it('should stop the server', function()
    claude_inline.stop()
    expect(claude_inline.is_running()).to_be_false()
  end)
end)

-- Print summary
print ''
print '=== Results ==='
print('Passed: ' .. passed)
print('Failed: ' .. failed)

-- Exit with appropriate code
vim.cmd(failed == 0 and 'q!' or 'cq!')
