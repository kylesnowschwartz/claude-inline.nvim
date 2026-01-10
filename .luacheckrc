-- Luacheck configuration for cursor-inline.nvim
-- Neovim plugin development

-- Globals provided by Neovim
globals = {
  "vim",
}

-- Read-only globals
read_globals = {
  "vim",
}

-- Ignore these warnings
ignore = {
  "212", -- unused argument (common in callbacks)
  "631", -- max line length
}

-- Files to exclude
exclude_files = {
  ".cloned-sources/**",
}
