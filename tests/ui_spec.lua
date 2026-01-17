-- UI smoke tests for claude-inline.nvim
-- These tests verify Neovim API calls work correctly (extmarks, buffers, etc.)
--
-- Run with: nvim --headless -u tests/minimal_init.lua +"lua require('tests.ui_spec').run()"

local M = {}

local ui = require 'claude-inline.ui'

-- Test helpers
local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format('%s: expected %s, got %s', msg or 'assertion failed', vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_true(value, msg)
  if not value then
    error(msg or 'expected true')
  end
end

local function assert_no_error(fn, msg)
  local ok, err = pcall(fn)
  if not ok then
    error(string.format('%s: %s', msg or 'unexpected error', err))
  end
end

-- Setup fresh state before each test
local function setup()
  -- Reset UI state
  ui.cleanup()
  if ui._state.sidebar_buf and vim.api.nvim_buf_is_valid(ui._state.sidebar_buf) then
    vim.api.nvim_buf_delete(ui._state.sidebar_buf, { force = true })
  end
  ui._state.sidebar_buf = nil
  ui._state.sidebar_win = nil
  ui._state.message_blocks = {}
end

-- Test: append_message creates extmark without error
-- This would have caught: "cannot set end_right_gravity without end_row"
local function test_append_message_creates_extmark()
  setup()
  ui.show_sidebar()

  assert_no_error(function()
    ui.append_message('user', 'Hello')
  end, 'append_message should not throw')

  local blocks = ui.get_all_blocks()
  assert_eq(#blocks, 1, 'should have one message block')
  assert_eq(blocks[1].role, 'user', 'block should be user role')
end

-- Test: update_last_message works with extmark lookup
local function test_update_last_message()
  setup()
  ui.show_sidebar()
  ui.append_message('assistant', '')

  assert_no_error(function()
    ui.update_last_message 'Streaming content...'
  end, 'update_last_message should not throw')

  -- Verify content was written
  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)
  local found = false
  for _, line in ipairs(lines) do
    if line:match 'Streaming' then
      found = true
      break
    end
  end
  assert_true(found, 'should find streaming content in buffer')
end

-- Test: multiple messages create multiple extmarks
local function test_multiple_messages()
  setup()
  ui.show_sidebar()

  ui.append_message('user', 'First message')
  ui.append_message('assistant', 'Response')
  ui.append_message('user', 'Follow up')

  local blocks = ui.get_all_blocks()
  assert_eq(#blocks, 3, 'should have three message blocks')
  assert_eq(blocks[1].role, 'user', 'first block should be user')
  assert_eq(blocks[2].role, 'assistant', 'second block should be assistant')
  assert_eq(blocks[3].role, 'user', 'third block should be user')
end

-- Test: clear resets extmarks
local function test_clear_resets_extmarks()
  setup()
  ui.show_sidebar()
  ui.append_message('user', 'Test')
  ui.append_message('assistant', 'Response')

  ui.clear()

  local blocks = ui.get_all_blocks()
  assert_eq(#blocks, 0, 'should have no message blocks after clear')
end

-- Test: show_thinking uses extmark lookup
local function test_show_thinking()
  setup()
  ui.show_sidebar()
  ui.append_message('assistant', '') -- Simulate loading state

  assert_no_error(function()
    ui.show_thinking()
  end, 'show_thinking should not throw')

  assert_true(ui._state.thinking_active, 'thinking should be active')
end

-- Run all tests
function M.run()
  local tests = {
    { name = 'append_message creates extmark', fn = test_append_message_creates_extmark },
    { name = 'update_last_message works', fn = test_update_last_message },
    { name = 'multiple messages create extmarks', fn = test_multiple_messages },
    { name = 'clear resets extmarks', fn = test_clear_resets_extmarks },
    { name = 'show_thinking uses extmarks', fn = test_show_thinking },
  }

  local passed = 0
  local failed = 0
  local errors = {}

  for _, test in ipairs(tests) do
    local ok, err = pcall(test.fn)
    if ok then
      passed = passed + 1
      print(string.format('  PASS: %s', test.name))
    else
      failed = failed + 1
      table.insert(errors, { name = test.name, err = err })
      print(string.format('  FAIL: %s', test.name))
      print(string.format('        %s', err))
    end
  end

  print ''
  print(string.format('Results: %d passed, %d failed', passed, failed))

  if failed > 0 then
    vim.cmd 'cquit 1' -- Exit with error code
  else
    vim.cmd 'qall!'
  end
end

return M
