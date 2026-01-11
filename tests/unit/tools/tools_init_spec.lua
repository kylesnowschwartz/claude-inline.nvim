require 'tests.busted_setup'

describe('Tool Registry', function()
  local tools

  before_each(function()
    -- Clear cached modules
    package.loaded['claude-inline.tools'] = nil
    package.loaded['claude-inline.tools.get_current_selection'] = nil
    package.loaded['claude-inline.tools.get_latest_selection'] = nil
    package.loaded['claude-inline.tools.open_diff'] = nil
    package.loaded['claude-inline.state'] = nil

    -- Mock state module
    package.loaded['claude-inline.state'] = {
      selected_text = '',
      main_bufnr = nil,
      selection_start = nil,
      selection_end = nil,
      selection_timestamp = nil,
      set_selection = function() end,
      clear_selection = function() end,
      highlight = {
        old_code = { ns = 1 },
        new_code = { ns = 2 },
      },
    }

    tools = require 'claude-inline.tools'
  end)

  after_each(function()
    package.loaded['claude-inline.tools'] = nil
    package.loaded['claude-inline.state'] = nil
  end)

  describe('setup', function()
    it('should register all tools', function()
      tools.setup()

      local tool_list = tools.get_tool_list()
      expect(#tool_list).to_be_at_least(3)
    end)

    it('should register getCurrentSelection', function()
      tools.setup()

      local found = false
      for _, t in ipairs(tools.get_tool_list()) do
        if t.name == 'getCurrentSelection' then
          found = true
          break
        end
      end
      expect(found).to_be_true()
    end)

    it('should register getLatestSelection', function()
      tools.setup()

      local found = false
      for _, t in ipairs(tools.get_tool_list()) do
        if t.name == 'getLatestSelection' then
          found = true
          break
        end
      end
      expect(found).to_be_true()
    end)

    it('should register openDiff', function()
      tools.setup()

      local found = false
      for _, t in ipairs(tools.get_tool_list()) do
        if t.name == 'openDiff' then
          found = true
          break
        end
      end
      expect(found).to_be_true()
    end)
  end)

  describe('get_tool_list', function()
    it('should return tools with name, description, and inputSchema', function()
      tools.setup()

      local tool_list = tools.get_tool_list()
      for _, t in ipairs(tool_list) do
        expect(t.name).not_to_be_nil()
        expect(t.description).not_to_be_nil()
        expect(t.inputSchema).not_to_be_nil()
      end
    end)
  end)

  describe('handle_invoke', function()
    it('should return error for unknown tool', function()
      tools.setup()

      local result = tools.handle_invoke({}, { name = 'nonexistentTool', arguments = {} })

      expect(result.error).not_to_be_nil()
      expect(result.error.code).to_be(-32601)
      assert_contains(result.error.message, 'Tool not found')
    end)

    it('should execute getCurrentSelection and return MCP format', function()
      tools.setup()

      local result = tools.handle_invoke({}, { name = 'getCurrentSelection', arguments = {} })

      expect(result.result).not_to_be_nil()
      expect(result.result.content).not_to_be_nil()
      expect(result.result.content[1].type).to_be 'text'
    end)

    it('should execute getLatestSelection and return MCP format', function()
      tools.setup()

      local result = tools.handle_invoke({}, { name = 'getLatestSelection', arguments = {} })

      expect(result.result).not_to_be_nil()
      expect(result.result.content).not_to_be_nil()
      expect(result.result.content[1].type).to_be 'text'
    end)
  end)

  describe('ERROR_CODES', function()
    it('should define standard JSON-RPC error codes', function()
      expect(tools.ERROR_CODES.PARSE_ERROR).to_be(-32700)
      expect(tools.ERROR_CODES.INVALID_REQUEST).to_be(-32600)
      expect(tools.ERROR_CODES.METHOD_NOT_FOUND).to_be(-32601)
      expect(tools.ERROR_CODES.INVALID_PARAMS).to_be(-32602)
      expect(tools.ERROR_CODES.INTERNAL_ERROR).to_be(-32000)
    end)
  end)
end)
