local M = {}

function M.setup(opts)
  local config = require("overwatch.config")
  local command = require("overwatch.command")
  local file_tree = require("overwatch.file_tree")
  config.setup(opts)
  command.setup()
  file_tree.setup()
end

function M.toggle()
  local command = require("overwatch.command")
  local state = require("overwatch.state")

  if state.is_active() then
    command.reset()
    return
  end

  local ok, commit_ref = pcall(state.get_commit_base)
  command.run(ok and commit_ref or "")
end

return M
