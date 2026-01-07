vim.bo.modifiable = false
vim.bo.buftype = "nofile"
vim.bo.swapfile = false
vim.bo.bufhidden = "wipe"
vim.bo.syntax = "overwatch_tree"

vim.wo.cursorline = true
vim.wo.statusline = "File Explorer"
vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.signcolumn = "no"
vim.wo.winfixwidth = true
vim.wo.foldenable = false
vim.wo.list = false
vim.wo.wrap = false

-- Set window-local CursorLine highlight (grey background)
vim.api.nvim_set_hl(0, "CursorLine", { bg = "#3b4261" })

local actions = require('overwatch.file_tree.actions')
local history = require('overwatch.history')
local state = require('overwatch.state')

-- Navigation keys auto-preview the file (move cursor AND open file)
vim.keymap.set("n", "j", function()
  actions.move_cursor_and_open_file(1)
end, { noremap = true, silent = true, buffer = true })

vim.keymap.set("n", "k", function()
  actions.move_cursor_and_open_file(-1)
end, { noremap = true, silent = true, buffer = true })

vim.keymap.set("n", "<Down>", function()
  actions.move_cursor_and_open_file(1)
end, { noremap = true, silent = true, buffer = true })

vim.keymap.set("n", "<Up>", function()
  actions.move_cursor_and_open_file(-1)
end, { noremap = true, silent = true, buffer = true })

vim.keymap.set("n", "R", function()
  actions.refresh()
end, { noremap = true, silent = true, buffer = true })

vim.keymap.set("n", "q", function()
  actions.close_tree()
end, { noremap = true, silent = true, buffer = true })

vim.keymap.set("n", "?", function()
  actions.show_help()
end, { noremap = true, silent = true, buffer = true })

-- h: Navigate to older commit (enter history mode or go further back)
vim.keymap.set("n", "h", function()
  history.navigate_older()
end, { noremap = true, silent = true, buffer = true })

-- l: Navigate to newer commit (if in history mode) OR open file (if in working tree mode)
vim.keymap.set("n", "l", function()
  if state.is_history_mode() then
    history.navigate_newer()
  else
    actions.toggle_node()
  end
end, { noremap = true, silent = true, buffer = true })

-- Enter opens file and moves focus to the buffer
vim.keymap.set("n", "<CR>", function()
  actions.open_and_focus()
end, { noremap = true, silent = true, buffer = true })
