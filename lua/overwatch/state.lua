-- State management for overwatch.nvim
local M = {}
local m = {
  commit_base = nil,
  active = false,
  -- History navigation state
  history_mode = false, -- true when browsing commit history
  history_stack = {}, -- commits navigated to (for going forward with 'l')
  history_index = 0, -- current position in history_stack (1-based)
}

-- Main window reference
M.main_win = nil

-- File tree window and buffer references
M.file_tree_win = nil
M.file_tree_buf = nil

-- Auto-refresh augroup ID
M.auto_refresh_augroup = nil

-- Flag to prevent recursive tree refresh when opening a file from the tree

-- Get the main content window (to navigate from tree back to content)
function M.get_main_window()
  if
    M.main_win
    and vim.api.nvim_win_is_valid(M.main_win)
    and (not M.file_tree_win or not vim.api.nvim_win_is_valid(M.file_tree_win) or M.main_win ~= M.file_tree_win)
  then
    return M.main_win
  end

  local valid_file_tree_win = M.file_tree_win and vim.api.nvim_win_is_valid(M.file_tree_win)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not valid_file_tree_win or win ~= M.file_tree_win then
      M.main_win = win
      return win
    end
  end

  vim.api.nvim_err_writeln("Overwatch: Could not find a suitable main window.")
  return nil
end

function M.set_commit_base(commit)
  m.commit_base = commit
  vim.api.nvim_exec_autocmds("User", { pattern = "OverwatchBaseCommitUpdated" })
end

---@return string
function M.get_commit_base()
  if m.commit_base == nil then
    error("Commit base is not set")
  end
  return m.commit_base
end

function M.set_active(val)
  m.active = not not val
end
function M.is_active()
  return m.active
end

-- History mode functions
function M.is_history_mode()
  return m.history_mode
end

function M.set_history_mode(val)
  m.history_mode = not not val
end

function M.get_history_stack()
  return m.history_stack
end

function M.get_history_index()
  return m.history_index
end

-- Push a commit onto the history stack (when navigating older)
function M.push_history(commit_hash)
  m.history_index = m.history_index + 1
  m.history_stack[m.history_index] = commit_hash
  -- Truncate any forward history
  for i = m.history_index + 1, #m.history_stack do
    m.history_stack[i] = nil
  end
end

-- Pop from history (when navigating newer), returns the commit to show
function M.pop_history()
  if m.history_index <= 1 then
    return nil
  end
  m.history_index = m.history_index - 1
  return m.history_stack[m.history_index]
end

function M.get_current_history_commit()
  if m.history_index > 0 then
    return m.history_stack[m.history_index]
  end
  return nil
end

function M.reset_history()
  m.history_mode = false
  m.history_stack = {}
  m.history_index = 0
end

return M
