require 'tests.busted_setup'

describe('Tool: getLatestSelection', function()
  local handler
  local mock_state

  before_each(function()
    package.loaded['claude-inline.tools.get_latest_selection'] = nil
    package.loaded['claude-inline.state'] = nil

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

    _G.vim.api.nvim_buf_is_valid = spy.new(function()
      return true
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function()
      return '/test/file.lua'
    end)

    handler = require('claude-inline.tools.get_latest_selection').handler
  end)

  after_each(function()
    package.loaded['claude-inline.tools.get_latest_selection'] = nil
    package.loaded['claude-inline.state'] = nil
  end)

  it('should return no selection message when selection is empty', function()
    mock_state.selected_text = ''

    local result = handler {}

    expect(result.content).to_be_table()
    expect(result.content[1].type).to_be 'text'

    local parsed = json_decode(result.content[1].text)
    expect(parsed.success).to_be_false()
    expect(parsed.message).to_be 'No selection available'
  end)

  it('should return selection data when available', function()
    mock_state.selected_text = 'selected text'
    mock_state.main_bufnr = 1
    mock_state.selection_start = { line = 0, character = 0 }
    mock_state.selection_end = { line = 0, character = 13 }
    mock_state.selection_timestamp = 1704067200

    local result = handler {}
    local parsed = json_decode(result.content[1].text)

    expect(parsed.success).to_be_true()
    expect(parsed.text).to_be 'selected text'
    expect(parsed.selection.isEmpty).to_be_false()
  end)

  it('should include timestamp when available', function()
    mock_state.selected_text = 'code'
    mock_state.main_bufnr = 1
    mock_state.selection_timestamp = 1704067200

    local result = handler {}
    local parsed = json_decode(result.content[1].text)

    expect(parsed.timestamp).to_be(1704067200)
  end)

  it('should return file path and URL when buffer is valid', function()
    mock_state.selected_text = 'test'
    mock_state.main_bufnr = 1

    local result = handler {}
    local parsed = json_decode(result.content[1].text)

    expect(parsed.filePath).to_be '/test/file.lua'
    expect(parsed.fileUrl).to_be 'file:///test/file.lua'
  end)

  it('should handle nil buffer gracefully', function()
    mock_state.selected_text = 'test'
    mock_state.main_bufnr = nil

    _G.vim.api.nvim_buf_is_valid = spy.new(function()
      return false
    end)

    local result = handler {}
    local parsed = json_decode(result.content[1].text)

    expect(parsed.success).to_be_true()
    expect(parsed.filePath).to_be ''
  end)

  it('should include position info when available', function()
    mock_state.selected_text = 'code'
    mock_state.main_bufnr = 1
    mock_state.selection_start = { line = 5, character = 10 }
    mock_state.selection_end = { line = 7, character = 3 }

    local result = handler {}
    local parsed = json_decode(result.content[1].text)

    expect(parsed.selection.start.line).to_be(5)
    expect(parsed.selection.start.character).to_be(10)
  end)
end)
