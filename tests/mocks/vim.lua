-- Mock vim API for running tests outside Neovim
local M = {}

M.api = {
  nvim_get_current_buf = function()
    return 1
  end,
  nvim_buf_get_name = function(bufnr)
    return '/mock/file.lua'
  end,
  nvim_buf_is_valid = function(bufnr)
    return true
  end,
  nvim_create_namespace = function(name)
    return 1
  end,
  nvim_get_option_value = function(name, opts)
    return ''
  end,
  nvim_buf_get_lines = function(bufnr, start, finish, strict)
    return {}
  end,
  nvim_win_get_buf = function(win)
    return 1
  end,
  nvim_win_get_config = function(win)
    return {}
  end,
  nvim_list_wins = function()
    return { 1 }
  end,
  nvim_set_current_win = function(win) end,
  nvim_win_set_buf = function(win, buf) end,
  nvim_create_buf = function(listed, scratch)
    return 1
  end,
  nvim_buf_set_name = function(buf, name) end,
  nvim_buf_set_lines = function(buf, start, finish, strict, lines) end,
  nvim_set_option_value = function(name, value, opts) end,
  nvim_create_augroup = function(name, opts)
    return 1
  end,
  nvim_create_autocmd = function(event, opts)
    return 1
  end,
  nvim_del_autocmd = function(id) end,
  nvim_win_is_valid = function(win)
    return true
  end,
  nvim_win_close = function(win, force) end,
  nvim_win_call = function(win, fn)
    fn()
  end,
  nvim_buf_delete = function(buf, opts) end,
}

M.fn = {
  filereadable = function(path)
    return 0
  end,
  bufnr = function(path)
    return -1
  end,
  fnameescape = function(path)
    return path
  end,
  expand = function(expr)
    return expr
  end,
}

M.cmd = function(cmd) end

M.schedule = function(fn)
  fn()
end

M.json = {
  encode = function(data)
    return require('tests.busted_setup').json_encode(data)
  end,
  decode = function(str)
    return require('tests.busted_setup').json_decode(str)
  end,
}

M.split = function(str, sep)
  local result = {}
  for part in string.gmatch(str, '([^' .. sep .. ']+)') do
    table.insert(result, part)
  end
  return result
end

M.tbl_extend = function(behavior, ...)
  local result = {}
  for _, tbl in ipairs { ... } do
    for k, v in pairs(tbl) do
      result[k] = v
    end
  end
  return result
end

M.notify = function(msg, level, opts) end

M.log = {
  levels = {
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3,
  },
}

M.filetype = {
  match = function(opts)
    local ext = opts.filename:match '%.([^.]+)$'
    local map = { lua = 'lua', py = 'python', js = 'javascript', ts = 'typescript' }
    return map[ext]
  end,
}

return M
