require 'tests.busted_setup'

describe('Tool: openDiff', function()
  local tool_module

  before_each(function()
    package.loaded['claude-inline.tools.open_diff'] = nil
    package.loaded['claude-inline.diff'] = nil

    -- Mock diff module
    package.loaded['claude-inline.diff'] = {
      open_diff_blocking = function()
        return { content = { { type = 'text', text = 'FILE_SAVED' } } }
      end,
    }

    tool_module = require 'claude-inline.tools.open_diff'
  end)

  after_each(function()
    package.loaded['claude-inline.tools.open_diff'] = nil
    package.loaded['claude-inline.diff'] = nil
  end)

  describe('module structure', function()
    it('should have correct name', function()
      expect(tool_module.name).to_be 'openDiff'
    end)

    it('should have a handler function', function()
      expect(tool_module.handler).to_be_function()
    end)

    it('should require coroutine context', function()
      expect(tool_module.requires_coroutine).to_be_true()
    end)

    it('should have a schema', function()
      expect(tool_module.schema).not_to_be_nil()
      expect(tool_module.schema.description).not_to_be_nil()
      expect(tool_module.schema.inputSchema).not_to_be_nil()
    end)
  end)

  describe('schema', function()
    it('should require old_file_path', function()
      local required = tool_module.schema.inputSchema.required
      local found = false
      for _, r in ipairs(required) do
        if r == 'old_file_path' then
          found = true
          break
        end
      end
      expect(found).to_be_true()
    end)

    it('should require new_file_path', function()
      local required = tool_module.schema.inputSchema.required
      local found = false
      for _, r in ipairs(required) do
        if r == 'new_file_path' then
          found = true
          break
        end
      end
      expect(found).to_be_true()
    end)

    it('should require new_file_contents', function()
      local required = tool_module.schema.inputSchema.required
      local found = false
      for _, r in ipairs(required) do
        if r == 'new_file_contents' then
          found = true
          break
        end
      end
      expect(found).to_be_true()
    end)

    it('should require tab_name', function()
      local required = tool_module.schema.inputSchema.required
      local found = false
      for _, r in ipairs(required) do
        if r == 'tab_name' then
          found = true
          break
        end
      end
      expect(found).to_be_true()
    end)
  end)

  describe('handler validation', function()
    it('should error when old_file_path is missing', function()
      local success, err = pcall(tool_module.handler, {
        new_file_path = '/new.lua',
        new_file_contents = 'content',
        tab_name = 'test',
      })

      expect(success).to_be_false()
      expect(err.code).to_be(-32602)
      assert_contains(err.data, 'old_file_path')
    end)

    it('should error when new_file_contents is missing', function()
      local success, err = pcall(tool_module.handler, {
        old_file_path = '/old.lua',
        new_file_path = '/new.lua',
        tab_name = 'test',
      })

      expect(success).to_be_false()
      expect(err.code).to_be(-32602)
      assert_contains(err.data, 'new_file_contents')
    end)

    it('should error when tab_name is missing', function()
      local success, err = pcall(tool_module.handler, {
        old_file_path = '/old.lua',
        new_file_path = '/new.lua',
        new_file_contents = 'content',
      })

      expect(success).to_be_false()
      expect(err.code).to_be(-32602)
      assert_contains(err.data, 'tab_name')
    end)

    it('should error when not in coroutine context', function()
      local success, err = pcall(tool_module.handler, {
        old_file_path = '/old.lua',
        new_file_path = '/new.lua',
        new_file_contents = 'content',
        tab_name = 'test',
      })

      expect(success).to_be_false()
      expect(err.code).to_be(-32000)
      assert_contains(err.data, 'coroutine')
    end)
  end)
end)
