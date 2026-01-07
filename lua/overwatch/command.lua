local M = {}

M.setup = function()
  vim.api.nvim_create_user_command("Overwatch", function(opts)
    M.run(opts.args)
  end, {
    nargs = "*",
    complete = function(ArgLead, CmdLine, _)
      if CmdLine:match("^Overwatch%s+") then
        local suggestions = { "HEAD", "HEAD~1", "main", "reset" }
        local filtered_suggestions = {}
        for _, suggestion in ipairs(suggestions) do
          if suggestion:sub(1, #ArgLead) == ArgLead then
            table.insert(filtered_suggestions, suggestion)
          end
        end
        return filtered_suggestions
      end
      return {}
    end,
  })
end

M.run = function(args)
  if args == "reset" then
    M.reset()
    return
  end

  local commit_ref = args

  if commit_ref == "" then
    commit_ref = "HEAD"
  end

  local git = require("overwatch.git")
  local state = require("overwatch.state")
  local file_tree = require("overwatch.file_tree")
  local cwd = vim.fn.getcwd()

  git.resolve_commit_hash(commit_ref, cwd, function(hash)
    if not hash then
      vim.api.nvim_echo({ { 'Error: could not resolve "' .. commit_ref .. '"', "ErrorMsg" } }, false, {})
      return
    end

    state.set_commit_base(hash)
    state.set_active(true)
    state.main_win = vim.api.nvim_get_current_win()

    file_tree.show(hash)
  end)

  return nil
end

function M.reset()
  -- Stop auto-refresh timer
  local tree_auto_refresh = require("overwatch.file_tree.auto_refresh")
  tree_auto_refresh.stop()

  local buffer = vim.api.nvim_get_current_buf()
  local config = require("overwatch.config")
  local ns_id = config.ns_id
  local hunk_store = require("overwatch.hunk_store")

  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.fn.sign_unplace("overwatch_diff", { buffer = buffer })

  hunk_store.clear(buffer)

  local state = require("overwatch.state")
  if state.auto_refresh_augroup then
    vim.api.nvim_del_augroup_by_id(state.auto_refresh_augroup)
    state.auto_refresh_augroup = nil
  end

  -- Clear history state
  state.reset_history()

  -- Clear hunk view buffer
  local hunk_view = require("overwatch.hunk_view")
  hunk_view.clear()

  -- Clear file tree state
  local tree_state = require("overwatch.file_tree.state")
  tree_state.reset_state()

  local windows = vim.api.nvim_list_wins()
  if not state.file_tree_win or not vim.api.nvim_win_is_valid(state.file_tree_win) then
    state.file_tree_win = nil
    state.file_tree_buf = nil
    state.main_win = nil
    state.set_active(false)
    return
  end

  if #windows == 1 then
    state.file_tree_win = nil
    state.file_tree_buf = nil
    state.main_win = nil
    state.set_active(false)
    return
  end

  vim.api.nvim_win_close(state.file_tree_win, true)

  state.file_tree_win = nil
  state.file_tree_buf = nil
  state.main_win = nil
  state.set_active(false)
end

return M
