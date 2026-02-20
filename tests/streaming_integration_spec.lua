--- Integration tests for settled message handling
--- Simulates Claude CLI message flow without spawning process
---
--- Run with: nvim --headless -u tests/minimal_init.lua +"lua require('tests.streaming_integration_spec').run()"

local M = {}

local init = require("claude-inline")
local ui = require("claude-inline.ui")
local state = require("claude-inline.ui.state")

-- Test helpers
local function assert_true(value, msg)
  if not value then
    error(msg or "expected true")
  end
end

local function setup()
  ui.cleanup()
  if state.sidebar_buf and vim.api.nvim_buf_is_valid(state.sidebar_buf) then
    vim.api.nvim_buf_delete(state.sidebar_buf, { force = true })
  end
  state.sidebar_buf = nil
  state.sidebar_win = nil
  state.message_blocks = {}
  state.content_blocks = {}

  init.setup({ debug = false })
  ui.show_sidebar()
  -- Start an assistant message context
  ui.append_message("assistant", "")
end

local function get_lines()
  return vim.api.nvim_buf_get_lines(state.sidebar_buf, 0, -1, false)
end

local function inject(msg)
  init._test.handle_message(msg)
end

--- Simulate complete tool flow with settled messages:
--- 1. assistant message with tool_use content block
--- 2. user message with tool_result content block
local function simulate_tool(opts)
  local tool_id = opts.id or ("tool_" .. math.random(100000, 999999))

  -- Assistant sends tool_use
  inject({
    type = "assistant",
    parent_tool_use_id = opts.parent_tool_use_id,
    message = {
      role = "assistant",
      content = {
        {
          type = "tool_use",
          id = tool_id,
          name = opts.name,
          input = opts.input or {},
        },
      },
    },
  })

  -- User returns tool_result
  inject({
    type = "user",
    message = {
      role = "user",
      content = {
        {
          type = "tool_result",
          tool_use_id = tool_id,
          content = opts.result_content or "",
          is_error = opts.is_error or false,
        },
      },
    },
    tool_use_result = opts.metadata,
  })

  return tool_id
end

-- Test: Read tool displays with line count
local function test_read_tool()
  setup()
  simulate_tool({
    name = "Read",
    input = { file_path = "lua/init.lua" },
    result_content = "-- file content",
    metadata = { file = { numLines = 42 } },
  })

  local lines = get_lines()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("Read%(lua/init%.lua%)") and line:match("42 lines") then
      found = true
    end
  end
  assert_true(found, "Read tool should show filename and line count")
end

-- Test: Bash error shows exit code
local function test_bash_error()
  setup()
  simulate_tool({
    name = "Bash",
    input = { command = "exit 1" },
    result_content = "",
    is_error = true,
    metadata = { exitCode = 1 },
  })

  local lines = get_lines()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("Bash%(exit 1%)") and line:match("[%*x]") then
      found = true
    end
  end
  assert_true(found, "Bash error should show error status")
end

-- Test: Parallel Tasks with interleaved children
-- In settled mode, each tool_use arrives as a separate assistant message.
-- parent_tool_use_id on the assistant message indicates child tools.
local function test_parallel_tasks_interleaved()
  setup()

  -- Task 1 starts
  inject({
    type = "assistant",
    message = {
      role = "assistant",
      content = {
        { type = "tool_use", id = "task_1", name = "Task", input = { description = "Find most starred repo agent 1" } },
      },
    },
  })

  -- Task 2 starts (parallel)
  inject({
    type = "assistant",
    message = {
      role = "assistant",
      content = {
        { type = "tool_use", id = "task_2", name = "Task", input = { description = "Find most starred repo agent 2" } },
      },
    },
  })

  -- Child of Task 1: first Bash command
  inject({
    type = "assistant",
    parent_tool_use_id = "task_1",
    message = {
      role = "assistant",
      content = {
        {
          type = "tool_use",
          id = "bash_1a",
          name = "Bash",
          input = { command = "gh search repos --sort stars --limit 1" },
        },
      },
    },
  })

  -- Child of Task 2: first Bash command (interleaved!)
  inject({
    type = "assistant",
    parent_tool_use_id = "task_2",
    message = {
      role = "assistant",
      content = {
        {
          type = "tool_use",
          id = "bash_2a",
          name = "Bash",
          input = { command = "gh search repos --sort stars --order desc --limit 1" },
        },
      },
    },
  })

  -- Task 1 child completes with error
  inject({
    type = "user",
    message = {
      role = "user",
      content = { { type = "tool_result", tool_use_id = "bash_1a", content = "error", is_error = true } },
    },
    tool_use_result = { exitCode = 1 },
  })

  -- Child of Task 1: retry with different command
  inject({
    type = "assistant",
    parent_tool_use_id = "task_1",
    message = {
      role = "assistant",
      content = {
        {
          type = "tool_use",
          id = "bash_1b",
          name = "Bash",
          input = { command = 'gh search repos "stars:>100000" --sort stars --limit 1' },
        },
      },
    },
  })

  -- Task 2 child completes successfully
  inject({
    type = "user",
    message = {
      role = "user",
      content = { { type = "tool_result", tool_use_id = "bash_2a", content = "freeCodeCamp", is_error = false } },
    },
    tool_use_result = { exitCode = 0 },
  })

  -- Task 1 retry completes
  inject({
    type = "user",
    message = {
      role = "user",
      content = { { type = "tool_result", tool_use_id = "bash_1b", content = "freeCodeCamp", is_error = false } },
    },
    tool_use_result = { exitCode = 0 },
  })

  -- Task 1 completes
  inject({
    type = "user",
    message = {
      role = "user",
      content = {
        {
          type = "tool_result",
          tool_use_id = "task_1",
          content = "The most starred repo is freeCodeCamp/freeCodeCamp.",
          is_error = false,
        },
      },
    },
    tool_use_result = { totalDurationMs = 12500, totalToolUseCount = 2 },
  })

  -- Task 2 completes
  inject({
    type = "user",
    message = {
      role = "user",
      content = {
        {
          type = "tool_result",
          tool_use_id = "task_2",
          content = "Confirmed: freeCodeCamp is the most starred.",
          is_error = false,
        },
      },
    },
    tool_use_result = { totalDurationMs = 8000, totalToolUseCount = 1 },
  })

  -- Verify buffer structure
  local lines = get_lines()

  -- Debug: print all lines
  print("    Buffer contents:")
  for i, line in ipairs(lines) do
    print(string.format("      %d: %s", i, line))
  end

  -- Find line indices for key elements
  local task1_header, task2_header
  local child_1a, child_1b, child_2a

  for i, line in ipairs(lines) do
    if line:match("%[Task task_1:") and line:match("agent 1") then
      task1_header = i
    end
    if line:match("%[Task task_2:") and line:match("agent 2") then
      task2_header = i
    end
    if line:match("Bash%(gh search repos %-%-sort stars %-%-limit 1%)") then
      child_1a = i
    end
    if line:match('Bash%(gh search repos "stars:>100000"') then
      child_1b = i
    end
    if line:match("Bash%(gh search repos %-%-sort stars %-%-order desc") then
      child_2a = i
    end
  end

  -- Assertions: Task headers should exist
  assert_true(task1_header, "Task 1 header should exist")
  assert_true(task2_header, "Task 2 header should exist")

  -- Task 1's children should appear after Task 1 header
  if child_1a then
    assert_true(child_1a > task1_header, "Child 1a should be after Task 1 header")
  end
  if child_1b then
    assert_true(child_1b > task1_header, "Child 1b should be after Task 1 header")
  end

  -- Task 2's child should exist
  if child_2a then
    assert_true(child_2a > task2_header, "Child 2a should be after Task 2 header")
  end

  -- Check for error status in buffer (bash_1a should show ✗)
  local error_found = false
  for _, line in ipairs(lines) do
    if line:match("Bash%(gh search repos %-%-sort stars %-%-limit 1%)") and line:match("✗") then
      error_found = true
    end
  end
  assert_true(error_found, "Failed Bash command should show error status (✗)")
end

-- Test: result message completes turn without error
local function test_result_completes_turn()
  setup()
  simulate_tool({
    name = "Read",
    input = { file_path = "test.lua" },
  })

  -- Send result message to complete turn
  inject({ type = "result", result = "" })

  -- Should not error - just verify message is closed
  assert_true(not state.current_message_open, "message should be closed after result")
end

-- Test: system messages are ignored
local function test_system_ignored()
  setup()
  local initial_line_count = #get_lines()

  inject({ type = "system", data = "hook response" })

  local final_line_count = #get_lines()
  assert_true(initial_line_count == final_line_count, "system messages should not modify buffer")
end

-- Test: stream_event messages are ignored
local function test_stream_events_ignored()
  setup()
  local initial_line_count = #get_lines()

  inject({
    type = "stream_event",
    event = {
      type = "content_block_delta",
      index = 0,
      delta = { type = "text_delta", text = "should be ignored" },
    },
  })

  local final_line_count = #get_lines()
  assert_true(initial_line_count == final_line_count, "stream_event messages should not modify buffer")
end

-- Test: Glob tool shows file count in metadata
local function test_glob_file_count()
  setup()
  simulate_tool({
    name = "Glob",
    input = { pattern = "**/*.lua" },
    result_content = "lua/init.lua\nlua/client.lua\nlua/ui.lua",
    metadata = { numFiles = 3 },
  })

  local lines = get_lines()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("Glob%(") and line:match("3 files") then
      found = true
    end
  end
  assert_true(found, "Glob tool should show file count")
end

-- Test: Grep tool shows match count
local function test_grep_match_count()
  setup()
  simulate_tool({
    name = "Grep",
    input = { pattern = "function" },
    result_content = "lua/init.lua:10: function foo()\nlua/ui.lua:20: function bar()",
    metadata = { numMatches = 2, numFiles = 2 },
  })

  local lines = get_lines()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("Grep%(") and (line:match("2 matches") or line:match("2 files")) then
      found = true
    end
  end
  assert_true(found, "Grep tool should show match or file count")
end

-- Test: Text and tools interleave correctly in settled mode
-- Scenario: Claude says something, runs two tools, then says more.
-- Each arrives as a separate settled assistant message.
local function test_text_tools_text_interleaved()
  setup()

  -- 1. Initial text
  inject({
    type = "assistant",
    message = {
      role = "assistant",
      content = {
        { type = "text", text = "Let me find and read the LICENSE file." },
      },
    },
  })

  -- 2. First tool: Glob
  simulate_tool({
    name = "Glob",
    input = { pattern = "**/LICENSE" },
    result_content = "/path/to/LICENSE",
    metadata = { numFiles = 1 },
  })

  -- 3. Second tool: Read
  simulate_tool({
    name = "Read",
    input = { file_path = "/path/to/LICENSE" },
    result_content = "GNU AFFERO GENERAL PUBLIC LICENSE...",
    metadata = { file = { numLines = 247 } },
  })

  -- 4. Final text after tools
  inject({
    type = "assistant",
    message = {
      role = "assistant",
      content = {
        {
          type = "text",
          text = "The AGPL v3 license sets these core limitations: Network copyleft requirement means you must share source code.",
        },
      },
    },
  })

  -- 5. Result
  inject({ type = "result", result = "" })

  -- Verify all content is visible
  local lines = get_lines()

  print("    Buffer contents:")
  for i, line in ipairs(lines) do
    print(string.format("      %d: %s", i, line))
  end

  local initial_text = false
  local glob_found = false
  local read_found = false
  local final_text = false

  for _, line in ipairs(lines) do
    if line:match("Let me find and read the LICENSE file") then
      initial_text = true
    end
    if line:match("Glob%(") then
      glob_found = true
    end
    if line:match("Read%(") then
      read_found = true
    end
    if line:match("AGPL v3 license") then
      final_text = true
    end
  end

  assert_true(initial_text, "Initial text should appear")
  assert_true(glob_found, "Glob tool should be displayed")
  assert_true(read_found, "Read tool should be displayed")
  assert_true(final_text, "Final text after tools MUST appear")
end

-- Test: Multiple text blocks arrive as separate assistant messages
local function test_multiple_text_blocks()
  setup()

  -- Tool execution
  simulate_tool({
    name = "Read",
    input = { file_path = "test.txt" },
    result_content = "file content here",
  })

  -- Final assistant text (separate settled message)
  inject({
    type = "assistant",
    message = {
      role = "assistant",
      content = {
        { type = "text", text = "Based on the file content, here is my analysis." },
      },
    },
  })

  -- Result
  inject({ type = "result", result = "" })

  local lines = get_lines()

  print("    Buffer contents:")
  for i, line in ipairs(lines) do
    print(string.format("      %d: %s", i, line))
  end

  local analysis_found = false
  for _, line in ipairs(lines) do
    if line:match("Based on the file content") or line:match("my analysis") then
      analysis_found = true
    end
  end

  assert_true(analysis_found, "Text after tool results MUST be displayed")
end

function M.run()
  local tests = {
    { "read tool display", test_read_tool },
    { "bash error status", test_bash_error },
    { "parallel tasks interleaved", test_parallel_tasks_interleaved },
    { "result completes turn", test_result_completes_turn },
    { "system messages ignored", test_system_ignored },
    { "stream events ignored", test_stream_events_ignored },
    { "glob file count", test_glob_file_count },
    { "grep match count", test_grep_match_count },
    { "text/tools/text interleaved", test_text_tools_text_interleaved },
    { "text after tool results", test_multiple_text_blocks },
  }

  local passed, failed = 0, 0
  for _, test in ipairs(tests) do
    local name, fn = test[1], test[2]
    local ok, err = pcall(fn)
    if ok then
      print("  PASS: settled: " .. name)
      passed = passed + 1
    else
      print("  FAIL: settled: " .. name)
      print("        " .. tostring(err))
      failed = failed + 1
    end
  end

  print("")
  print(string.format("Settled message results: %d passed, %d failed", passed, failed))

  return passed, failed
end

return M
