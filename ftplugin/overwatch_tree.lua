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

local actions = require('overwatch.file_tree.actions')

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

vim.keymap.set("n", "l", function()
  actions.toggle_node()
end, { noremap = true, silent = true, buffer = true })
