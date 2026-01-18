# claude-inline.nvim development commands

# Default: run all checks
default: check test

# Check Lua syntax and run linter
check:
    @echo "Checking Lua syntax..."
    @find lua -name "*.lua" -exec luajit -bl {} \; > /dev/null
    @echo "Running luacheck..."
    @luacheck lua/ tests/ --config .luacheckrc

# Run tests in headless Neovim
test:
    @echo "Running tests..."
    @nvim --headless -u tests/minimal_init.lua +"lua require('tests.ui_spec').run()"

# Format with stylua (if available)
format:
    @command -v stylua > /dev/null && stylua lua/ tests/ || echo "stylua not found, skipping format"

# Run a quick smoke test (faster than full test suite)
smoke:
    @echo "Syntax check..."
    @find lua -name "*.lua" -exec luajit -bl {} \; > /dev/null
    @echo "Quick smoke test..."
    @nvim --headless -u tests/minimal_init.lua +"lua require('claude-inline.ui').show_sidebar(); require('claude-inline.ui').append_message('user', 'test'); print('OK'); vim.cmd('qall!')"

# Clean generated files
clean:
    @rm -f /tmp/claude-inline-debug.log
    @echo "Cleaned"

# Watch for changes and run tests (requires entr)
watch:
    @echo "Watching for changes... (Ctrl-C to stop)"
    @find lua tests -name "*.lua" | entr -c just test

# Show test output with verbose logging
test-verbose:
    @nvim --headless -u tests/minimal_init.lua +"lua require('claude-inline').setup({debug=true}); require('tests.ui_spec').run()"
