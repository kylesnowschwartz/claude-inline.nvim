-- UI smoke tests for claude-inline.nvim
-- These tests verify Neovim API calls work correctly (extmarks, buffers, etc.)
--
-- Run with: nvim --headless -u tests/minimal_init.lua +"lua require('tests.ui_spec').run()"

local M = {}

local ui = require("claude-inline.ui")

-- Test helpers
local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(
      string.format("%s: expected %s, got %s", msg or "assertion failed", vim.inspect(expected), vim.inspect(actual))
    )
  end
end

local function assert_true(value, msg)
  if not value then
    error(msg or "expected true")
  end
end

local function assert_no_error(fn, msg)
  local ok, err = pcall(fn)
  if not ok then
    error(string.format("%s: %s", msg or "unexpected error", err))
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
    ui.append_message("user", "Hello")
  end, "append_message should not throw")

  local blocks = ui.get_all_blocks()
  assert_eq(#blocks, 1, "should have one message block")
  assert_eq(blocks[1].role, "user", "block should be user role")
end

-- Test: update_last_message works with extmark lookup
local function test_update_last_message()
  setup()
  ui.show_sidebar()
  ui.append_message("assistant", "")

  assert_no_error(function()
    ui.update_last_message("Streaming content...")
  end, "update_last_message should not throw")

  -- Verify content was written
  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)
  local found = false
  for _, line in ipairs(lines) do
    if line:match("Streaming") then
      found = true
      break
    end
  end
  assert_true(found, "should find streaming content in buffer")
end

-- Test: multiple messages create multiple extmarks
local function test_multiple_messages()
  setup()
  ui.show_sidebar()

  ui.append_message("user", "First message")
  ui.append_message("assistant", "Response")
  ui.append_message("user", "Follow up")

  local blocks = ui.get_all_blocks()
  assert_eq(#blocks, 3, "should have three message blocks")
  assert_eq(blocks[1].role, "user", "first block should be user")
  assert_eq(blocks[2].role, "assistant", "second block should be assistant")
  assert_eq(blocks[3].role, "user", "third block should be user")
end

-- Test: clear resets extmarks
local function test_clear_resets_extmarks()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "Test")
  ui.append_message("assistant", "Response")

  ui.clear()

  local blocks = ui.get_all_blocks()
  assert_eq(#blocks, 0, "should have no message blocks after clear")
end

-- Test: user messages have correct header format (no fold markers)
local function test_user_message_header()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "Hello")

  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)
  assert_eq(lines[1], "You", "user message should have You header")
  assert_eq(lines[2], "Hello", "user message content should follow header")
  -- Verify no fold markers in content
  for _, line in ipairs(lines) do
    assert_true(not line:match("{{{"), "should not have {{{ fold markers")
    assert_true(not line:match("}}}"), "should not have }}} fold markers")
  end
end

-- Test: assistant messages have correct header format
local function test_assistant_message_header()
  setup()
  ui.show_sidebar()
  ui.append_message("assistant", "Response")

  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)
  assert_eq(lines[1], "Claude", "assistant message should have Claude header")
  assert_true(ui._state.current_message_open, "current_message_open should be true")
end

-- Test: close_current_message updates state
local function test_close_current_message()
  setup()
  ui.show_sidebar()
  ui.append_message("assistant", "Response text")

  assert_true(ui._state.current_message_open, "message should be open before close")

  ui.close_current_message()

  assert_true(not ui._state.current_message_open, "message should be closed after close_current_message")
end

-- Test: foldexpr returns correct levels for message headers
local function test_foldexpr_message_headers()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "Hello")
  ui.append_message("assistant", "Response")

  -- Set buffer context for foldexpr
  vim.api.nvim_set_current_buf(ui._state.sidebar_buf)

  -- Test user header (line 1)
  vim.v.lnum = 1
  assert_eq(ui.foldexpr(), ">1", "user header should start level 1 fold")

  -- Test assistant header (line 5 after user message + blanks)
  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line == "Claude" then
      vim.v.lnum = i
      assert_eq(ui.foldexpr(), ">1", "assistant header should start level 1 fold")
      break
    end
  end
end

-- Test: foldtext returns preview for messages
local function test_foldtext_preview()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "What is the meaning of life?")

  vim.api.nvim_set_current_buf(ui._state.sidebar_buf)
  vim.v.foldstart = 1

  local text = ui.foldtext()
  assert_true(text:match("^You"), "foldtext should start with role")
  assert_true(text:match("meaning of life"), "foldtext should include content preview")
end

-- Test: fold_all and unfold_all functions exist and don't error
local function test_fold_unfold_functions()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "Test 1")
  ui.append_message("assistant", "Response 1")
  ui.close_current_message()

  assert_no_error(function()
    ui.fold_all()
  end, "fold_all should not throw")

  assert_no_error(function()
    ui.unfold_all()
  end, "unfold_all should not throw")
end

-- =============================================================================
-- Integration tests for fold behavior
-- These tests verify the actual fold state using vim's fold functions
-- =============================================================================

--- Helper to check fold state in sidebar window context
---@param lnum number Line number to check
---@return number foldlevel, number foldclosed
local function get_fold_state(lnum)
  local level, closed
  vim.api.nvim_win_call(ui._state.sidebar_win, function()
    level = vim.fn.foldlevel(lnum)
    closed = vim.fn.foldclosed(lnum)
  end)
  return level, closed
end

--- Helper to process pending scheduled callbacks (for vim.schedule)
local function flush_scheduled()
  -- Run a blocking command to flush the event loop
  vim.cmd("redraw")
  -- Also try vim.wait with a small timeout to process scheduled funcs
  vim.wait(10, function()
    return false
  end)
end

-- Test: foldlevel is correctly set for message headers
local function test_fold_integration_foldlevel()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "Hello")

  -- Set window context and check fold level
  vim.api.nvim_set_current_win(ui._state.sidebar_win)

  local level = vim.fn.foldlevel(1)
  assert_eq(level, 1, "user message header should have foldlevel 1")

  local level2 = vim.fn.foldlevel(2)
  assert_eq(level2, 1, "user message content should have foldlevel 1")
end

-- Test: manual fold close/open works with zc/zo
local function test_fold_integration_manual_zc_zo()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "Hello")

  vim.api.nvim_win_call(ui._state.sidebar_win, function()
    -- Verify fold is open initially
    local closed_before = vim.fn.foldclosed(1)
    assert_eq(closed_before, -1, "fold should be open initially")

    -- Close the fold
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! zc")

    -- Verify fold is closed
    local closed_after = vim.fn.foldclosed(1)
    assert_eq(closed_after, 1, "fold should be closed after zc")

    -- Open the fold
    vim.cmd("normal! zo")
    local closed_final = vim.fn.foldclosed(1)
    assert_eq(closed_final, -1, "fold should be open after zo")
  end)
end

-- Test: fold_all closes all message folds
local function test_fold_integration_fold_all()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "First")
  ui.append_message("assistant", "Response")
  flush_scheduled()

  -- Both folds should be closeable with fold_all
  ui.fold_all()

  local _, closed1 = get_fold_state(1)
  assert_true(closed1 > 0, "first message fold should be closed after fold_all")

  -- Find assistant message line
  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line == "Claude" then
      local _, closed2 = get_fold_state(i)
      assert_true(closed2 > 0, "assistant message fold should be closed after fold_all")
      break
    end
  end
end

-- Test: unfold_all opens all message folds
local function test_fold_integration_unfold_all()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "First")
  ui.append_message("assistant", "Response")
  flush_scheduled()

  -- Close all folds first
  ui.fold_all()

  -- Then open them
  ui.unfold_all()

  local _, closed1 = get_fold_state(1)
  assert_eq(closed1, -1, "first message fold should be open after unfold_all")
end

-- Test: streaming updates don't break fold state
local function test_fold_integration_streaming_stability()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "Question")
  ui.append_message("assistant", "")
  flush_scheduled()

  -- Simulate streaming updates
  ui.update_last_message("Part 1...")
  ui.update_last_message("Part 1... Part 2...")
  ui.update_last_message("Part 1... Part 2... Part 3.")

  -- Fold structure should still be intact
  local level, _ = get_fold_state(1)
  assert_eq(level, 1, "user message should still have foldlevel 1 after streaming")
end

-- Test: buffer content structure is correct for folding
local function test_fold_integration_buffer_structure()
  setup()
  ui.show_sidebar()
  ui.append_message("user", "Hello world")
  ui.append_message("assistant", "Hi there")
  flush_scheduled()

  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)

  -- Verify structure: header, content, blank lines
  assert_eq(lines[1], "You", "line 1 should be user header")
  assert_eq(lines[2], "Hello world", "line 2 should be user content")

  -- Find assistant header
  local found_assistant = false
  for i, line in ipairs(lines) do
    if line == "Claude" then
      found_assistant = true
      assert_eq(lines[i + 1], "Hi there", "assistant content should follow header")
      break
    end
  end
  assert_true(found_assistant, "should find assistant header in buffer")
end

-- =============================================================================
-- Tool Use Component Tests
-- =============================================================================

-- Test: show_tool_use creates tool block in buffer
local function test_show_tool_use()
  setup()
  ui.show_sidebar()
  ui.append_message("assistant", "")

  assert_no_error(function()
    ui.show_tool_use("tool_123", "Read", { file_path = "test.lua" })
  end, "show_tool_use should not throw")

  -- Verify content block state
  assert_true(ui._state.content_blocks["tool_123"] ~= nil, "content block should be tracked")
  assert_eq(ui._state.content_blocks["tool_123"].type, "tool_use", "block type should be tool_use")
  assert_eq(ui._state.content_blocks["tool_123"].name, "Read", "tool name should be stored")

  -- Verify buffer content shows one-line format: ToolName(param) ...
  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)
  local found_tool = false
  for _, line in ipairs(lines) do
    if line:match("Read%(test%.lua%)") then
      found_tool = true
      break
    end
  end
  assert_true(found_tool, "should find tool line in buffer")
end

-- Test: show_tool_result updates tool line with status
local function test_show_tool_result()
  setup()
  ui.show_sidebar()
  ui.append_message("assistant", "")
  ui.show_tool_use("tool_result_test", "Read", { file_path = "test.lua" })

  assert_no_error(function()
    ui.show_tool_result("tool_result_test", "file contents", false)
  end, "show_tool_result should not throw")

  -- Verify tool line now shows success status (✓)
  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)
  local found_success = false
  for _, line in ipairs(lines) do
    if line:match("Read%(test%.lua%)") and line:match("✓") then
      found_success = true
      break
    end
  end
  assert_true(found_success, "should find tool line with success status")
end

-- Test: show_tool_result handles errors
local function test_show_tool_result_error()
  setup()
  ui.show_sidebar()
  ui.append_message("assistant", "")
  ui.show_tool_use("error_test", "Bash", { command = "exit 1" })

  assert_no_error(function()
    ui.show_tool_result("error_test", "command failed", true)
  end, "show_tool_result with error should not throw")

  -- Verify tool line shows error status (✗)
  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)
  local found_error = false
  for _, line in ipairs(lines) do
    if line:match("Bash%(exit 1%)") and line:match("✗") then
      found_error = true
      break
    end
  end
  assert_true(found_error, "should find tool line with error status")
end

-- Test: tool lines don't break assistant message fold structure
local function test_foldexpr_tool_headers()
  setup()
  ui.show_sidebar()
  ui.append_message("assistant", "")
  ui.show_tool_use("fold_test", "Read", { file_path = "test.lua" })

  vim.api.nvim_set_current_buf(ui._state.sidebar_buf)

  -- Assistant header should still start level 1 fold
  -- Line 1 might be empty if the Claude header is elsewhere, find it
  local lines = vim.api.nvim_buf_get_lines(ui._state.sidebar_buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line == "Claude" then
      vim.v.lnum = i
      assert_eq(ui.foldexpr(), ">1", "assistant header should start level 1 fold")
      break
    end
  end
end

-- Test: clear resets content_blocks state
local function test_clear_resets_content_blocks()
  setup()
  ui.show_sidebar()
  ui.append_message("assistant", "")
  ui.show_tool_use("clear_test", "bash", {})

  assert_true(ui._state.content_blocks["clear_test"] ~= nil, "content block should exist before clear")

  ui.clear()

  assert_true(next(ui._state.content_blocks) == nil, "content_blocks should be empty after clear")
end

-- Run all tests
function M.run()
  local tests = {
    -- Unit tests
    { name = "append_message creates extmark", fn = test_append_message_creates_extmark },
    { name = "update_last_message works", fn = test_update_last_message },
    { name = "multiple messages create extmarks", fn = test_multiple_messages },
    { name = "clear resets extmarks", fn = test_clear_resets_extmarks },
    { name = "user message header format", fn = test_user_message_header },
    { name = "assistant message header format", fn = test_assistant_message_header },
    { name = "close_current_message works", fn = test_close_current_message },
    { name = "foldexpr returns correct levels", fn = test_foldexpr_message_headers },
    { name = "foldtext returns preview", fn = test_foldtext_preview },
    { name = "fold_all/unfold_all functions", fn = test_fold_unfold_functions },
    -- Integration tests for fold behavior
    { name = "integration: foldlevel detection", fn = test_fold_integration_foldlevel },
    { name = "integration: manual zc/zo", fn = test_fold_integration_manual_zc_zo },
    { name = "integration: fold_all closes folds", fn = test_fold_integration_fold_all },
    { name = "integration: unfold_all opens folds", fn = test_fold_integration_unfold_all },
    { name = "integration: streaming stability", fn = test_fold_integration_streaming_stability },
    { name = "integration: buffer structure", fn = test_fold_integration_buffer_structure },
    -- Tool use component tests
    { name = "tool: show_tool_use creates block", fn = test_show_tool_use },
    { name = "tool: show_tool_result creates block", fn = test_show_tool_result },
    { name = "tool: show_tool_result handles error", fn = test_show_tool_result_error },
    { name = "tool: foldexpr handles tool headers", fn = test_foldexpr_tool_headers },
    { name = "tool: clear resets content_blocks", fn = test_clear_resets_content_blocks },
  }

  local passed = 0
  local failed = 0
  local errors = {}

  for _, test in ipairs(tests) do
    local ok, err = pcall(test.fn)
    if ok then
      passed = passed + 1
      print(string.format("  PASS: %s", test.name))
    else
      failed = failed + 1
      table.insert(errors, { name = test.name, err = err })
      print(string.format("  FAIL: %s", test.name))
      print(string.format("        %s", err))
    end
  end

  print("")
  print(string.format("Results: %d passed, %d failed", passed, failed))

  if failed > 0 then
    vim.cmd("cquit 1") -- Exit with error code
  else
    vim.cmd("qall!")
  end
end

return M
