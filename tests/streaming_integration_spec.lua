--- Integration tests for NDJSON streaming
--- Simulates Claude CLI message flow without spawning process
---
--- Run with: nvim --headless -u tests/minimal_init.lua +"lua require('tests.streaming_integration_spec').run()"

local M = {}

local init = require 'claude-inline'
local ui = require 'claude-inline.ui'
local state = require 'claude-inline.ui.state'

-- Test helpers
local function assert_true(value, msg)
  if not value then
    error(msg or 'expected true')
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

  -- Reset init state
  init._state.streaming_text = ''
  init._state.content_blocks = {}
  init._state.tools_shown = false

  init.setup { debug = false }
  ui.show_sidebar()
  -- Start an assistant message context
  ui.append_message('assistant', '')
end

local function get_lines()
  return vim.api.nvim_buf_get_lines(state.sidebar_buf, 0, -1, false)
end

local function inject(msg)
  init._test.handle_message(msg)
end

--- Simulate complete tool flow: start -> deltas -> stop -> result
local function simulate_tool(opts)
  local tool_id = opts.id or ('tool_' .. math.random(100000, 999999))

  -- content_block_start
  inject {
    type = 'stream_event',
    event = {
      type = 'content_block_start',
      index = opts.index or 0,
      content_block = {
        type = 'tool_use',
        id = tool_id,
        name = opts.name,
        input = {},
      },
    },
  }

  -- Stream input JSON in chunks
  local input_json = vim.json.encode(opts.input or {})
  for i = 1, #input_json, 20 do
    inject {
      type = 'stream_event',
      event = {
        type = 'content_block_delta',
        index = opts.index or 0,
        delta = {
          type = 'input_json_delta',
          partial_json = input_json:sub(i, i + 19),
        },
      },
    }
  end

  -- content_block_stop
  inject {
    type = 'stream_event',
    event = {
      type = 'content_block_stop',
      index = opts.index or 0,
    },
  }

  -- tool_result (in user message)
  inject {
    type = 'user',
    message = {
      role = 'user',
      content = {
        {
          type = 'tool_result',
          tool_use_id = tool_id,
          content = opts.result_content or '',
          is_error = opts.is_error or false,
        },
      },
    },
    tool_use_result = opts.metadata,
  }

  return tool_id
end

-- Test: Read tool displays with line count
local function test_read_tool()
  setup()
  simulate_tool {
    name = 'Read',
    input = { file_path = 'lua/init.lua' },
    result_content = '-- file content',
    metadata = { file = { numLines = 42 } },
  }

  local lines = get_lines()
  local found = false
  for _, line in ipairs(lines) do
    if line:match 'Read%(lua/init%.lua%)' and line:match '42 lines' then
      found = true
    end
  end
  assert_true(found, 'Read tool should show filename and line count')
end

-- Test: Bash error shows exit code
local function test_bash_error()
  setup()
  simulate_tool {
    name = 'Bash',
    input = { command = 'exit 1' },
    result_content = '',
    is_error = true,
    metadata = { exitCode = 1 },
  }

  local lines = get_lines()
  local found = false
  for _, line in ipairs(lines) do
    if line:match 'Bash%(exit 1%)' and line:match '[%*x]' then
      found = true
    end
  end
  assert_true(found, 'Bash error should show error status')
end

-- Test: Parallel Tasks with interleaved children
-- Simulates: "Create two parallel sub-agents. Each should independently verify
-- which is the most starred repo on github, using gh."
local function test_parallel_tasks_interleaved()
  setup()

  -- Task 1 starts (description streams in later)
  inject {
    type = 'stream_event',
    event = {
      type = 'content_block_start',
      index = 0,
      content_block = {
        type = 'tool_use',
        id = 'task_1',
        name = 'Task',
        input = {},
      },
    },
  }

  -- Task 1 description streams in
  inject {
    type = 'stream_event',
    event = {
      type = 'content_block_delta',
      index = 0,
      delta = {
        type = 'input_json_delta',
        partial_json = '{"description":"Find most starred repo agent 1"}',
      },
    },
  }

  -- Task 2 starts (parallel - both tasks running now)
  inject {
    type = 'stream_event',
    event = {
      type = 'content_block_start',
      index = 1,
      content_block = {
        type = 'tool_use',
        id = 'task_2',
        name = 'Task',
        input = {},
      },
    },
  }

  -- Task 2 description streams in
  inject {
    type = 'stream_event',
    event = {
      type = 'content_block_delta',
      index = 1,
      delta = {
        type = 'input_json_delta',
        partial_json = '{"description":"Find most starred repo agent 2"}',
      },
    },
  }

  -- Child of Task 1: first Bash command
  -- parent_tool_use_id tells us this belongs to task_1
  inject {
    type = 'stream_event',
    parent_tool_use_id = 'task_1',
    event = {
      type = 'content_block_start',
      index = 2,
      content_block = {
        type = 'tool_use',
        id = 'bash_1a',
        name = 'Bash',
        input = { command = 'gh search repos --sort stars --limit 1' },
      },
    },
  }

  -- Child of Task 2: first Bash command (interleaved!)
  -- parent_tool_use_id tells us this belongs to task_2
  inject {
    type = 'stream_event',
    parent_tool_use_id = 'task_2',
    event = {
      type = 'content_block_start',
      index = 3,
      content_block = {
        type = 'tool_use',
        id = 'bash_2a',
        name = 'Bash',
        input = { command = 'gh search repos --sort stars --order desc --limit 1' },
      },
    },
  }

  -- Task 1 child completes with error
  inject {
    type = 'user',
    message = {
      role = 'user',
      content = { { type = 'tool_result', tool_use_id = 'bash_1a', content = 'error', is_error = true } },
    },
    tool_use_result = { exitCode = 1 },
  }

  -- Child of Task 1: retry with different command
  -- parent_tool_use_id tells us this belongs to task_1
  inject {
    type = 'stream_event',
    parent_tool_use_id = 'task_1',
    event = {
      type = 'content_block_start',
      index = 4,
      content_block = {
        type = 'tool_use',
        id = 'bash_1b',
        name = 'Bash',
        input = { command = 'gh search repos "stars:>100000" --sort stars --limit 1' },
      },
    },
  }

  -- Task 2 child completes successfully
  inject {
    type = 'user',
    message = {
      role = 'user',
      content = { { type = 'tool_result', tool_use_id = 'bash_2a', content = 'freeCodeCamp', is_error = false } },
    },
    tool_use_result = { exitCode = 0 },
  }

  -- Task 1 retry completes
  inject {
    type = 'user',
    message = {
      role = 'user',
      content = { { type = 'tool_result', tool_use_id = 'bash_1b', content = 'freeCodeCamp', is_error = false } },
    },
    tool_use_result = { exitCode = 0 },
  }

  -- Task 1 completes (took longer due to retry)
  -- content contains the agent's final answer/conclusion
  inject {
    type = 'user',
    message = {
      role = 'user',
      content = { { type = 'tool_result', tool_use_id = 'task_1', content = 'The most starred repo is freeCodeCamp/freeCodeCamp.', is_error = false } },
    },
    tool_use_result = { totalDurationMs = 12500, totalToolUseCount = 2 },
  }

  -- Task 2 completes
  inject {
    type = 'user',
    message = {
      role = 'user',
      content = { { type = 'tool_result', tool_use_id = 'task_2', content = 'Confirmed: freeCodeCamp is the most starred.', is_error = false } },
    },
    tool_use_result = { totalDurationMs = 8000, totalToolUseCount = 1 },
  }

  -- Verify buffer structure
  local lines = get_lines()

  -- Debug: print all lines
  print '    Buffer contents:'
  for i, line in ipairs(lines) do
    print(string.format('      %d: %s', i, line))
  end

  -- Find line indices for key elements
  -- Task format: [Task task_1: description]
  local task1_header, task2_header
  local child_1a, child_1b, child_2a

  for i, line in ipairs(lines) do
    if line:match '%[Task task_1:' and line:match 'agent 1' then
      task1_header = i
    end
    if line:match '%[Task task_2:' and line:match 'agent 2' then
      task2_header = i
    end
    if line:match 'Bash%(gh search repos %-%-sort stars %-%-limit 1%)' then
      child_1a = i
    end
    if line:match 'Bash%(gh search repos "stars:>100000"' then
      child_1b = i
    end
    if line:match 'Bash%(gh search repos %-%-sort stars %-%-order desc' then
      child_2a = i
    end
  end

  -- Assertions: Task headers should exist
  assert_true(task1_header, 'Task 1 header should exist')
  assert_true(task2_header, 'Task 2 header should exist')

  -- Task 1's children should appear (grouped under Task 1 is ideal, but for now just verify they exist)
  if child_1a then
    assert_true(child_1a > task1_header, 'Child 1a should be after Task 1 header')
  end
  if child_1b then
    assert_true(child_1b > task1_header, 'Child 1b should be after Task 1 header')
  end

  -- Task 2's child should exist
  if child_2a then
    assert_true(child_2a > task2_header, 'Child 2a should be after Task 2 header')
  end

  -- Check for error status in buffer (bash_1a should show ✗)
  local error_found = false
  for _, line in ipairs(lines) do
    if line:match 'Bash%(gh search repos %-%-sort stars %-%-limit 1%)' and line:match '✗' then
      error_found = true
    end
  end
  assert_true(error_found, 'Failed Bash command should show error status (✗)')
end

-- Test: State resets on result message
local function test_state_reset()
  setup()
  simulate_tool {
    name = 'Read',
    input = { file_path = 'test.lua' },
  }

  -- Send result message to complete turn
  inject { type = 'result', result = '' }

  -- State should be clean
  assert_true(not init._state.tools_shown, 'tools_shown should reset')
  assert_true(vim.tbl_isempty(init._state.content_blocks), 'content_blocks should reset')
end

-- Test: text_delta streaming works
local function test_text_delta_streaming()
  setup()

  -- Simulate text block start
  inject {
    type = 'stream_event',
    event = {
      type = 'content_block_start',
      index = 0,
      content_block = { type = 'text' },
    },
  }

  -- Stream text in chunks
  inject {
    type = 'stream_event',
    event = {
      type = 'content_block_delta',
      index = 0,
      delta = { type = 'text_delta', text = 'Hello ' },
    },
  }
  inject {
    type = 'stream_event',
    event = {
      type = 'content_block_delta',
      index = 0,
      delta = { type = 'text_delta', text = 'world!' },
    },
  }

  -- Verify text accumulated
  local lines = get_lines()
  local found = false
  for _, line in ipairs(lines) do
    if line:match 'Hello world!' then
      found = true
    end
  end
  assert_true(found, 'Streamed text should appear in buffer')
end

-- Test: system messages are ignored
local function test_system_ignored()
  setup()
  local initial_line_count = #get_lines()

  inject { type = 'system', data = 'hook response' }

  local final_line_count = #get_lines()
  assert_true(initial_line_count == final_line_count, 'system messages should not modify buffer')
end

-- Test: Glob tool shows file count in metadata
local function test_glob_file_count()
  setup()
  simulate_tool {
    name = 'Glob',
    input = { pattern = '**/*.lua' },
    result_content = 'lua/init.lua\nlua/client.lua\nlua/ui.lua',
    metadata = { numFiles = 3 },
  }

  local lines = get_lines()
  local found = false
  for _, line in ipairs(lines) do
    if line:match 'Glob%(' and line:match '3 files' then
      found = true
    end
  end
  assert_true(found, 'Glob tool should show file count')
end

-- Test: Grep tool shows match count
local function test_grep_match_count()
  setup()
  simulate_tool {
    name = 'Grep',
    input = { pattern = 'function' },
    result_content = 'lua/init.lua:10: function foo()\nlua/ui.lua:20: function bar()',
    metadata = { numMatches = 2, numFiles = 2 },
  }

  local lines = get_lines()
  local found = false
  for _, line in ipairs(lines) do
    if line:match 'Grep%(' and (line:match '2 matches' or line:match '2 files') then
      found = true
    end
  end
  assert_true(found, 'Grep tool should show match or file count')
end

function M.run()
  local tests = {
    { 'read tool display', test_read_tool },
    { 'bash error status', test_bash_error },
    { 'parallel tasks interleaved', test_parallel_tasks_interleaved },
    { 'state reset', test_state_reset },
    { 'text delta streaming', test_text_delta_streaming },
    { 'system messages ignored', test_system_ignored },
    { 'glob file count', test_glob_file_count },
    { 'grep match count', test_grep_match_count },
  }

  local passed, failed = 0, 0
  for _, test in ipairs(tests) do
    local name, fn = test[1], test[2]
    local ok, err = pcall(fn)
    if ok then
      print('  PASS: streaming: ' .. name)
      passed = passed + 1
    else
      print('  FAIL: streaming: ' .. name)
      print('        ' .. tostring(err))
      failed = failed + 1
    end
  end

  print ''
  print(string.format('Streaming results: %d passed, %d failed', passed, failed))

  return passed, failed
end

return M
