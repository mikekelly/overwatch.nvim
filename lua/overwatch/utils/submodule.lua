-- utils/submodule.lua
-- Utilities for detecting and getting status of git submodules

local Job = require("overwatch.utils.job")

local M = {}

--- Parse git submodule status output
--- Format: [+-U ]<sha> <path> (optional description)
--- - ' ' = submodule is checked out at correct commit
--- - '+' = submodule HEAD differs from parent's recorded commit
--- - '-' = submodule not initialized
--- - 'U' = submodule has merge conflicts
---@param output string
---@return table[] submodules Array of {path, status, sha}
local function parse_submodule_status(output)
  local submodules = {}
  for line in (output or ""):gmatch("[^\r\n]+") do
    local status_char = line:sub(1, 1)
    local rest = line:sub(2)
    local sha, path = rest:match("^(%x+)%s+([^%s%(]+)")
    if sha and path then
      table.insert(submodules, {
        path = path,
        status = status_char,
        sha = sha,
      })
    end
  end
  return submodules
end

--- Get list of submodules with their status (async)
---@param root_dir string The git repository root
---@param callback fun(submodules: table[]|nil) Called with array of submodule info or nil on error
function M.get_submodules(root_dir, callback)
  Job.run(
    { "git", "submodule", "status" },
    { cwd = root_dir },
    function(stdout, code)
      if code ~= 0 then
        callback(nil)
        return
      end
      local submodules = parse_submodule_status(stdout)
      callback(submodules)
    end
  )
end

--- Check if a submodule has changes (dirty working tree)
---@param root_dir string The parent repo root
---@param submodule_path string Relative path to submodule
---@param callback fun(has_changes: boolean, changed_files: table|nil)
function M.get_submodule_changes(root_dir, submodule_path, callback)
  local full_path = root_dir .. "/" .. submodule_path
  Job.run(
    { "git", "status", "--porcelain", "--untracked-files=all" },
    { cwd = full_path },
    function(stdout, code)
      if code ~= 0 then
        callback(false, nil)
        return
      end

      local changed_files = {}
      local has_changes = false

      for line in (stdout or ""):gmatch("[^\r\n]+") do
        local status = line:sub(1, 2)
        local file = line:sub(4)

        -- Handle renames
        if status:match("^R") or status:match("^C") then
          local parts = vim.split(file, " -> ")
          if #parts == 2 then
            file = parts[2]
          end
        end

        if file and file ~= "" then
          local file_path = full_path .. "/" .. file
          status = (status:gsub("%s", " ") .. " "):sub(1, 2)
          changed_files[file_path] = status
          has_changes = true
        end
      end

      callback(has_changes, has_changes and changed_files or nil)
    end
  )
end

--- Get all submodules that have changes (modified HEAD or dirty working tree)
--- Only fetches details for submodules that appear modified
---@param root_dir string The git repository root
---@param callback fun(submodules: table[]|nil) Array of {path, status, sha, dirty, changed_files}
function M.get_changed_submodules(root_dir, callback)
  M.get_submodules(root_dir, function(submodules)
    if not submodules or #submodules == 0 then
      callback({})
      return
    end

    local results = {}
    local pending = 0
    local completed = 0

    for _, sub in ipairs(submodules) do
      -- Only check dirty state for submodules that might have changes
      -- '+' means HEAD differs, ' ' could still be dirty
      pending = pending + 1

      M.get_submodule_changes(root_dir, sub.path, function(has_changes, changed_files)
        completed = completed + 1

        -- Include if: HEAD differs (+) OR has uncommitted changes
        if sub.status == "+" or has_changes then
          table.insert(results, {
            path = sub.path,
            status = sub.status,
            sha = sub.sha,
            dirty = has_changes,
            changed_files = changed_files,
          })
        end

        -- All done
        if completed == pending then
          -- Sort by path for consistent display
          table.sort(results, function(a, b)
            return a.path < b.path
          end)
          callback(results)
        end
      end)
    end

    -- Handle case with no submodules to check
    if pending == 0 then
      callback({})
    end
  end)
end

return M
