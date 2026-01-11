-- Minimal test runner for Neovim headless mode
-- Run with: nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/run_tests.lua" -c "quit"
--
-- This provides busted-like describe/it/before_each/after_each without requiring
-- the full busted framework installation.

local pass_count = 0
local fail_count = 0
local current_describe = ''
local before_each_fns = {}
local after_each_fns = {}

-- Busted-compatible API
_G.describe = function(name, fn)
  local parent = current_describe
  current_describe = parent == '' and name or (parent .. ' > ' .. name)
  local parent_before = vim.deepcopy(before_each_fns)
  local parent_after = vim.deepcopy(after_each_fns)
  fn()
  current_describe = parent
  before_each_fns = parent_before
  after_each_fns = parent_after
end

_G.it = function(name, fn)
  local test_name = current_describe .. ' > ' .. name

  -- Run before_each hooks
  for _, hook in ipairs(before_each_fns) do
    hook()
  end

  local ok, err = pcall(fn)

  -- Run after_each hooks
  for _, hook in ipairs(after_each_fns) do
    pcall(hook)
  end

  if ok then
    print('[PASS] ' .. test_name)
    pass_count = pass_count + 1
  else
    print('[FAIL] ' .. test_name)
    print('       ' .. tostring(err))
    fail_count = fail_count + 1
  end
end

_G.before_each = function(fn)
  table.insert(before_each_fns, fn)
end

_G.after_each = function(fn)
  table.insert(after_each_fns, fn)
end

-- Spy implementation
_G.spy = {
  new = function(fn)
    local calls = {}
    local wrapper = function(...)
      table.insert(calls, { ... })
      if fn then
        return fn(...)
      end
    end
    return setmetatable({}, {
      __call = function(_, ...)
        return wrapper(...)
      end,
      __index = {
        was_called = function()
          return #calls > 0
        end,
        was_called_with = function(...)
          local expected = { ... }
          for _, call in ipairs(calls) do
            local match = true
            for i, v in ipairs(expected) do
              if call[i] ~= v then
                match = false
                break
              end
            end
            if match then
              return true
            end
          end
          return false
        end,
      },
    })
  end,
}

-- Load busted_setup for helpers
vim.opt.rtp:append '.'
require 'tests.busted_setup'

-- Find and run all spec files
local spec_files = vim.fn.glob('tests/unit/**/*_spec.lua', false, true)

print '\n=== Running Test Specs ===\n'

for _, file in ipairs(spec_files) do
  print('Loading: ' .. file)
  before_each_fns = {}
  after_each_fns = {}
  current_describe = ''

  local ok, err = pcall(dofile, file)
  if not ok then
    print('[ERROR] Failed to load ' .. file .. ': ' .. tostring(err))
    fail_count = fail_count + 1
  end
end

print '\n=== Results ==='
print('Passed: ' .. pass_count)
print('Failed: ' .. fail_count)
print ''

if fail_count > 0 then
  vim.cmd 'cquit 1'
end
