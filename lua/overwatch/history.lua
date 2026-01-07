-- history.lua - Commit history navigation for Overwatch
local M = {}

local Job = require("overwatch.utils.job")

-- Get parent commit of a given commit
-- Returns nil for root commits
function M.get_parent_commit(commit_hash, cwd, callback)
  Job.run({ "git", "rev-parse", commit_hash .. "^" }, { cwd = cwd }, function(out, code, _)
    vim.schedule(function()
      if code == 0 then
        callback(vim.trim(out))
      else
        callback(nil) -- Root commit or error
      end
    end)
  end)
end

-- Get commit message (short, one line)
function M.get_commit_message(commit_hash, cwd, callback)
  Job.run({ "git", "log", "--format=%s", "-n", "1", commit_hash }, { cwd = cwd }, function(out, code, _)
    vim.schedule(function()
      if code == 0 then
        callback(vim.trim(out))
      else
        callback(nil)
      end
    end)
  end)
end

-- Navigate to an older commit (h key)
function M.navigate_older()
  local state = require("overwatch.state")
  local tree_state = require("overwatch.file_tree.state")
  local cwd = vim.fn.getcwd()

  -- Determine current commit
  local current
  if state.is_history_mode() then
    current = tree_state.current_commit
  else
    current = state.get_commit_base()
  end

  if not current then
    vim.api.nvim_echo({ { "No commit to navigate from", "WarningMsg" } }, false, {})
    return
  end

  M.get_parent_commit(current, cwd, function(parent)
    if not parent then
      vim.api.nvim_echo({ { "At root commit", "WarningMsg" } }, false, {})
      return
    end

    -- Enter history mode if not already
    if not state.is_history_mode() then
      state.set_history_mode(true)
      -- Push the original commit first so we can return to it
      state.push_history(current)
    end

    -- Push the parent commit
    state.push_history(parent)

    -- Show the commit diff
    M.show_commit(parent)
  end)
end

-- Navigate to a newer commit (l key in history mode)
-- Returns true if handled (was in history mode), false if not
function M.navigate_newer()
  local state = require("overwatch.state")

  if not state.is_history_mode() then
    return false -- Caller should handle as file open
  end

  local prev_commit = state.pop_history()

  if not prev_commit then
    -- At the most recent commit in history, exit history mode
    state.set_history_mode(false)
    state.reset_history()

    -- Return to working tree view
    local commit = state.get_commit_base()
    local file_tree = require("overwatch.file_tree")
    file_tree.show(commit)
    return true
  end

  -- Show the previous (newer) commit
  M.show_commit(prev_commit)
  return true
end

-- Show a specific commit's changes
function M.show_commit(commit_hash)
  local tree_state = require("overwatch.file_tree.state")
  local cwd = vim.fn.getcwd()

  -- Get parent for diff computation
  M.get_parent_commit(commit_hash, cwd, function(parent)
    tree_state.current_commit = commit_hash
    tree_state.parent_commit = parent -- nil for root commits

    -- Get commit message for display
    M.get_commit_message(commit_hash, cwd, function(message)
      tree_state.commit_message = message

      -- Refresh the tree to show files changed in this commit
      local file_tree = require("overwatch.file_tree")
      file_tree.show_history_commit(commit_hash, parent)
    end)
  end)
end

return M
