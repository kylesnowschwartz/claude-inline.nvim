-- Test script for terminal sidebar functionality
-- Run in Neovim with: :luafile test_server.lua
-- NOTE: Must be run in GUI Neovim, not headless (terminal splits need display)

-- Add the plugin to runtime path
vim.opt.rtp:append '.'

-- Clear cached modules to get fresh load
for name, _ in pairs(package.loaded) do
  if name:match '^claude%-inline' then
    package.loaded[name] = nil
  end
end

local claude_inline = require 'claude-inline'

print '=== Testing Terminal Sidebar (Phase 3) ==='

-- Step 1: Setup the plugin
print '\n1. Setting up plugin...'
claude_inline.setup {}
print 'Setup complete'

-- Step 2: Test toggle_terminal (should auto-start server)
print '\n2. Testing toggle_terminal (auto-starts server)...'
claude_inline.toggle_terminal()

-- Step 3: Check server status
print '\n3. Server status:'
local status = claude_inline.get_status()
print(vim.inspect(status))

-- Step 4: Check terminal state
print '\n4. Terminal state:'
print('Is terminal open? ' .. tostring(claude_inline.is_terminal_open()))

-- Step 5: Check lock file
print '\n5. Checking lock file...'
local lock_files = vim.fn.glob(vim.fn.expand '~/.claude/ide/*.lock', false, true)
print('Lock files found: ' .. #lock_files)
for _, f in ipairs(lock_files) do
  local name = vim.fn.fnamemodify(f, ':t')
  print('  - ' .. name)
end

print '\n=== VERIFICATION STEPS ==='
print '1. Claude CLI should appear in right sidebar split'
print '2. Server should show "Claude Code connected" when CLI starts'
print '3. Toggle again to hide: :lua require("claude-inline").toggle_terminal()'
print '4. Toggle again to show (same session): :lua require("claude-inline").toggle_terminal()'
print ''
print 'Commands:'
print '  :lua require("claude-inline").toggle_terminal()  -- Toggle visibility'
print '  :lua require("claude-inline").is_terminal_open() -- Check if visible'
print '  :lua require("claude-inline").close_terminal()   -- Close completely'
print '  :lua require("claude-inline").stop()             -- Stop WebSocket server'
print ''
print('Server port: ' .. tostring(status.port))
