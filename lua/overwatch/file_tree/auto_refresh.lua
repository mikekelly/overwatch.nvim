-- File tree auto-refresh with git status caching
local M = {}

local Job = require("overwatch.utils.job")
local Config = require("overwatch.config")
local submodule_utils = require("overwatch.utils.submodule")

-- State
local timer = nil
local last_status_hash = nil
local last_submodule_hash = nil
local is_running = false

-- Simple hash function for comparing git status output
local function hash_string(str)
  local h = 0
  for i = 1, #str do
    h = (h * 31 + string.byte(str, i)) % 2147483647
  end
  return h
end

-- Get current git status as a string
local function get_git_status(root_path, callback)
  Job.run(
    { "git", "status", "--porcelain" },
    { cwd = root_path },
    function(stdout, code)
      if code == 0 then
        callback(stdout)
      else
        callback(nil)
      end
    end
  )
end

-- Build a hash string from submodule data for change detection
local function hash_submodules(submodules)
  if not submodules or #submodules == 0 then
    return ""
  end
  local parts = {}
  for _, sub in ipairs(submodules) do
    local sub_str = sub.path .. ":" .. (sub.status or "") .. ":" .. (sub.dirty and "dirty" or "clean")
    if sub.changed_files then
      for path, status in pairs(sub.changed_files) do
        sub_str = sub_str .. ";" .. path .. "=" .. status
      end
    end
    table.insert(parts, sub_str)
  end
  table.sort(parts)
  return table.concat(parts, "|")
end

-- Check if git status has changed and trigger refresh if needed
local function check_and_refresh()
  if is_running then
    return
  end

  local tree_state = require("overwatch.file_tree.state")

  -- Check if tree is still open
  if not tree_state.buffer or not vim.api.nvim_buf_is_valid(tree_state.buffer) then
    M.stop()
    return
  end

  if not tree_state.window or not vim.api.nvim_win_is_valid(tree_state.window) then
    M.stop()
    return
  end

  local root_path = tree_state.root_path
  if not root_path then
    return
  end

  is_running = true

  get_git_status(root_path, function(status)
    if not status then
      is_running = false
      return
    end

    local current_hash = hash_string(status)
    local status_changed = last_status_hash ~= nil and current_hash ~= last_status_hash

    -- Check submodules if enabled
    local submodules_config = Config.values.file_tree.submodules or {}
    if submodules_config.enabled then
      submodule_utils.get_changed_submodules(root_path, function(submodules)
        is_running = false

        local submodule_hash = hash_submodules(submodules)
        local submodule_changed = last_submodule_hash ~= nil and submodule_hash ~= last_submodule_hash

        -- Trigger refresh if either changed
        if status_changed or submodule_changed then
          vim.schedule(function()
            if tree_state.buffer and vim.api.nvim_buf_is_valid(tree_state.buffer) then
              local actions = require("overwatch.file_tree.actions")
              actions.refresh(true) -- force=true to bypass current buffer check
            else
              vim.api.nvim_echo({{"Auto-refresh: buffer invalid, skipping", "WarningMsg"}}, true, {})
            end
          end)
        end

        last_status_hash = current_hash
        last_submodule_hash = submodule_hash
      end)
    else
      is_running = false

      -- Trigger refresh if status changed
      if status_changed then
        vim.schedule(function()
          if tree_state.buffer and vim.api.nvim_buf_is_valid(tree_state.buffer) then
            local actions = require("overwatch.file_tree.actions")
            actions.refresh()
          end
        end)
      end

      last_status_hash = current_hash
    end
  end)
end

-- Start the auto-refresh timer
function M.start()
  if timer then
    return -- Already running
  end

  local config = Config.values.file_tree or {}
  if not config.auto_refresh then
    return
  end

  local interval = config.refresh_interval or 2000

  -- Initialize the hash with current status
  local tree_state = require("overwatch.file_tree.state")
  if tree_state.root_path then
    get_git_status(tree_state.root_path, function(status)
      if status then
        last_status_hash = hash_string(status)
      end
    end)

    -- Initialize submodule hash if enabled
    local submodules_config = config.submodules or {}
    if submodules_config.enabled then
      submodule_utils.get_changed_submodules(tree_state.root_path, function(submodules)
        if submodules then
          last_submodule_hash = hash_submodules(submodules)
        end
      end)
    end
  end

  timer = vim.uv.new_timer()
  timer:start(interval, interval, vim.schedule_wrap(function()
    check_and_refresh()
  end))
end

-- Stop the auto-refresh timer
function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  last_status_hash = nil
  last_submodule_hash = nil
  is_running = false
end

-- Reset cached hash (call after manual refresh)
function M.reset_cache()
  last_status_hash = nil
  last_submodule_hash = nil
end

return M
