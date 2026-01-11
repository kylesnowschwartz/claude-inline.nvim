require 'tests.busted_setup'

describe('Tool: getCurrentSelection', function()
  local handler
  local mock_state

  before_each(function()
    -- Clear cached modules
    package.loaded['claude-inline.tools.get_current_selection'] = nil
    package.loaded['claude-inline.state'] = nil

    -- Create mock state
    mock_state = {
      selected_text = '',
      main_bufnr = nil,
      selection_start = nil,
      selection_end = nil,
      selection_timestamp = nil,
      highlight = {
        old_code = { ns = 1 },
        new_code = { ns = 2 },
      },
    }
    package.loaded['claude-inline.state'] = mock_state

    -- Mock vim.api
    _G.vim.api.nvim_get_current_buf = spy.new(function()
      return 1
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function(bufnr)
      return '/test/file.lua'
    end)
    _G.vim.api.nvim_buf_is_valid = spy.new(function(bufnr)
      return true
    end)

    handler = require('claude-inline.tools.get_current_selection').handler
  end)

  after_each(function()
    package.loaded['claude-inline.tools.get_current_selection'] = nil
    package.loaded['claude-inline.state'] = nil
  end)

  it('should return empty selection when no text is selected', function()
    mock_state.selected_text = ''

    local result = handler {}

    expect(result).to_be_table()
    expect(result.content).to_be_table()
    expect(result.content[1].type).to_be 'text'

    local parsed = json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
    expect(parsed.text).to_be ''
    expect(parsed.selection.isEmpty).to_be_true()
  end)

  it('should return selection data when text is selected', function()
    mock_state.selected_text = 'selected code'
    mock_state.main_bufnr = 1
    mock_state.selection_start = { line = 5, character = 0 }
    mock_state.selection_end = { line = 5, character = 13 }

    local result = handler {}

    expect(result).to_be_table()
    expect(result.content).to_be_table()
    expect(result.content[1].type).to_be 'text'

    local parsed = json_decode(result.content[1].text)
    expect(parsed.success).to_be_true()
    expect(parsed.text).to_be 'selected code'
    expect(parsed.selection.isEmpty).to_be_false()
    expect(parsed.filePath).to_be '/test/file.lua'
  end)

  it('should include position info when available', function()
    mock_state.selected_text = 'code'
    mock_state.main_bufnr = 1
    mock_state.selection_start = { line = 10, character = 4 }
    mock_state.selection_end = { line = 10, character = 8 }

    local result = handler {}
    local parsed = json_decode(result.content[1].text)

    expect(parsed.selection.start.line).to_be(10)
    expect(parsed.selection.start.character).to_be(4)
  end)

  it('should return no active editor message when buffer name is empty', function()
    mock_state.selected_text = ''
    _G.vim.api.nvim_buf_get_name = spy.new(function()
      return ''
    end)

    local result = handler {}
    local parsed = json_decode(result.content[1].text)

    expect(parsed.success).to_be_false()
    expect(parsed.message).to_be 'No active editor found'
  end)

  it('should include fileUrl in response', function()
    mock_state.selected_text = 'test'
    mock_state.main_bufnr = 1

    local result = handler {}
    local parsed = json_decode(result.content[1].text)

    expect(parsed.fileUrl).to_be 'file:///test/file.lua'
  end)
end)
