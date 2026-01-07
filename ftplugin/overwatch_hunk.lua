-- Filetype plugin for overwatch hunk view buffer
vim.bo.modifiable = false
vim.bo.buftype = "nofile"
vim.bo.swapfile = false
vim.bo.bufhidden = "hide"

vim.wo.cursorline = true
vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.signcolumn = "no"
vim.wo.foldenable = false
vim.wo.wrap = false

-- Set syntax to diff for proper highlighting
vim.bo.syntax = "diff"

-- Set window-local statusline
vim.wo.statusline = "Diff View"

-- q closes the buffer/window
vim.keymap.set("n", "q", function()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()

  -- Try to close window, or just hide the buffer
  local windows = vim.api.nvim_list_wins()
  if #windows > 1 then
    vim.api.nvim_win_close(win, true)
  else
    -- If it's the last window, just switch to an empty buffer
    vim.cmd("enew")
  end
end, { noremap = true, silent = true, buffer = true })
