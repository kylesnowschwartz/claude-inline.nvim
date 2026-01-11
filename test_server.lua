-- Test script for WebSocket server
-- Run in Neovim with: :luafile test_server.lua

-- Add the plugin to runtime path
vim.opt.rtp:append '.'

-- Clear cached modules to get fresh load
for name, _ in pairs(package.loaded) do
  if name:match '^cursor%-inline' then
    package.loaded[name] = nil
  end
end

local cursor_inline = require 'claude-inline'

print '=== Testing WebSocket Server ==='

-- Step 1: Start the server
print '\n1. Starting WebSocket server...'

local success, err = cursor_inline.start {
  on_message = function(client, msg)
    print('Message from ' .. client.id .. ': ' .. vim.inspect(msg):sub(1, 100))
  end,
}

if not success then
  print('FAILED to start server: ' .. (err or 'unknown'))
  return
end

-- Step 2: Check server status
print '\n2. Server status:'
local status = cursor_inline.get_status()
print(vim.inspect(status))

-- Step 3: Check lock file was created
print '\n3. Checking lock file...'
local lock_files = vim.fn.glob(vim.fn.expand '~/.claude/ide/*.lock', false, true)
print('Lock files found: ' .. #lock_files)
for _, f in ipairs(lock_files) do
  local name = vim.fn.fnamemodify(f, ':t')
  print('  - ' .. name)

  -- Read and show content
  local file = io.open(f, 'r')
  if file then
    local content = file:read '*all'
    file:close()
    local ok, data = pcall(vim.json.decode, content)
    if ok then
      print('    ideName: ' .. (data.ideName or 'unknown'))
      print('    port: ' .. (name:match '^(%d+)' or 'unknown'))
    end
  end
end

print '\n=== SERVER IS RUNNING ==='
print 'To test connection from Claude Code CLI:'
print '  1. Open a new terminal'
print('  2. Set environment: export CLAUDE_CODE_SSE_PORT=' .. tostring(status.port))
print '  3. Set environment: export ENABLE_IDE_INTEGRATION=true'
print '  4. Run: claude'
print ''
print 'To stop the server:'
print '  :lua require("claude-inline").stop()'
print ''
print('Current port: ' .. tostring(status.port))
