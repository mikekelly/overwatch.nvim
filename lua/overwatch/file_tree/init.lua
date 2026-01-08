local M = {}
local git = require("overwatch.git")
local global_state = require("overwatch.state")
local FileTree = require("overwatch.file_tree.tree")
local render = require("overwatch.file_tree.render")
local actions = require("overwatch.file_tree.actions")
local tree_auto_refresh = require("overwatch.file_tree.auto_refresh")
local config = require("overwatch.config")
local submodule_utils = require("overwatch.utils.submodule")
local position_cursor_on_first_file

-- Calculate optimal width for the file tree based on content
local function calculate_tree_width(buf)
  local width_config = config.values.file_tree.width
  local min_width = width_config.min
  local max_percent = width_config.max_percent
  local padding = width_config.padding

  -- Calculate max width from screen percentage
  local screen_width = vim.o.columns
  local max_width = math.floor(screen_width * max_percent / 100)

  -- Find the longest line in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local max_line_width = 0
  for _, line in ipairs(lines) do
    local display_width = vim.fn.strdisplaywidth(line)
    if display_width > max_line_width then
      max_line_width = display_width
    end
  end

  -- Calculate optimal width with padding
  local optimal_width = max_line_width + padding

  -- Clamp between min and max
  return math.max(min_width, math.min(optimal_width, max_width))
end

-- Resize the tree window to fit content
local function resize_tree_window(win, buf)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local width = calculate_tree_width(buf)
  vim.api.nvim_win_set_width(win, width)
end

function M.setup()
  vim.api.nvim_create_autocmd("User", {
    pattern = "OverwatchBaseCommitUpdated",
    callback = function()
      local commit_hash = global_state.get_commit_base()
      M.show(commit_hash)
    end,
  })
end

function M.create_file_tree_buffer(buffer_path, diff_only, commit_ref_arg)
  local tree_state = require("overwatch.file_tree.state")
  tree_state.root_path = buffer_path
  tree_state.diff_only = diff_only
  tree_state.commit_ref = commit_ref_arg

  local dir
  local path_exists = vim.fn.filereadable(buffer_path) == 1 or vim.fn.isdirectory(buffer_path) == 1
  if path_exists then
    dir = vim.fn.isdirectory(buffer_path) == 1 and buffer_path or vim.fn.fnamemodify(buffer_path, ":h")
  else
    dir = vim.fn.fnamemodify(buffer_path, ":h")
    if vim.fn.isdirectory(dir) ~= 1 then
      dir = vim.fn.getcwd()
    end
  end

  local is_git_repo = git.is_git_repo(dir)
  local root_dir = dir
  if is_git_repo then
    local git_root_cmd = string.format("cd %s && git rev-parse --show-toplevel 2>/dev/null", vim.fn.shellescape(dir))
    local git_root = vim.trim(vim.fn.system(git_root_cmd))
    if vim.v.shell_error == 0 and git_root ~= "" and vim.fn.isdirectory(git_root .. "/.git") == 1 then
      root_dir = git_root
    else
      local check_dir = dir
      local max_depth = 10
      for _ = 1, max_depth do
        if vim.fn.isdirectory(check_dir .. "/.git") == 1 then
          root_dir = check_dir
          break
        end
        local parent = vim.fn.fnamemodify(check_dir, ":h")
        if parent == check_dir then
          break
        end
        check_dir = parent
      end
    end
  end

  if vim.fn.isdirectory(root_dir) ~= 1 then
    root_dir = vim.fn.getcwd()
  end

  local commit_ref = commit_ref_arg

  local tree = FileTree.new(root_dir)

  local buf = vim.api.nvim_create_buf(false, true)

  local buffer_name = "Overwatch: File Tree"
  if commit_ref then
    buffer_name = buffer_name .. " (" .. commit_ref .. ")"
  elseif diff_only then
    buffer_name = buffer_name .. " (Diff)"
  end

  pcall(vim.api.nvim_buf_set_name, buf, buffer_name)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "overwatch_tree"

  render.render_tree(tree, buf)

  tree:update_git_status(root_dir, diff_only, commit_ref, function()
    -- Function to finish rendering after submodules are fetched (or skipped)
    local function finish_render()
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        render.render_tree(tree, buf)

        local win = tree_state.window or global_state.file_tree_win
        if not win then
          return
        end
        if not vim.api.nvim_win_is_valid(win) then
          return
        end
        vim.api.nvim_set_current_win(win)
        position_cursor_on_first_file(buf, win)
        -- Auto-open first file in the tree while keeping focus in the tree window
        do
          local first_node
          local line_count = vim.api.nvim_buf_line_count(buf)
          local ts = require("overwatch.file_tree.state")
          for i = 3, line_count - 1 do
            local n = ts.line_to_node[i]
            if n and not n.is_dir then
              first_node = n
              break
            end
          end
          if first_node then
            actions.open_file_node(first_node)
          end
        end

        -- Resize window to fit content
        resize_tree_window(win, buf)

        -- Start auto-refresh timer
        tree_auto_refresh.start()
      end)
    end

    -- Check if submodules are enabled
    local submodules_config = config.values.file_tree.submodules or {}
    if submodules_config.enabled then
      submodule_utils.get_changed_submodules(root_dir, function(submodules)
        tree_state.submodules = submodules or {}
        finish_render()
      end)
    else
      tree_state.submodules = {}
      finish_render()
    end
  end)

  return buf
end

-- Removed: auto_select_and_open_first_file (auto-open behavior)

position_cursor_on_first_file = function(buffer, window)
  if not buffer or not window or not vim.api.nvim_buf_is_valid(buffer) or not vim.api.nvim_win_is_valid(window) then
    return
  end

  local first_file_line = -1
  local line_count = vim.api.nvim_buf_line_count(buffer)
  local tree_state = require("overwatch.file_tree.state")
  for i = 3, line_count - 1 do
    local node = tree_state.line_to_node[i]
    if node and not node.is_dir then
      first_file_line = i
      break
    end
  end

  if first_file_line > 0 then
    local target_line = first_file_line + 1
    local current_line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(window))
    if target_line <= current_line_count then
      vim.api.nvim_win_set_cursor(window, { target_line, 0 })
    end
  end
end

--- @param commit_hash string The commit hash to compare against.
function M.show(commit_hash)
  local file_path = vim.fn.getcwd()
  local diff_only = true -- Always show diff only for a specific commit

  -- Check if tree window already exists and is valid
  local tree_state = require("overwatch.file_tree.state")
  if
    tree_state.window
    and vim.api.nvim_win_is_valid(tree_state.window)
    and tree_state.buffer
    and vim.api.nvim_buf_is_valid(tree_state.buffer)
  then
    local new_buf = M.create_file_tree_buffer(file_path, diff_only, commit_hash)

    vim.api.nvim_win_set_buf(tree_state.window, new_buf)
    -- The create function updates tree_state.buffer, but we also need to update global state
    global_state.file_tree_buf = new_buf -- Update global state reference

    -- Focus the tree window
    vim.api.nvim_set_current_win(tree_state.window)

    -- Position cursor on the first file in the updated tree
    position_cursor_on_first_file(new_buf, tree_state.window)

    -- Auto-open first file while keeping focus in the tree (diffview-like)
    do
      local first_node
      local line_count = vim.api.nvim_buf_line_count(new_buf)
      local tree_state = require("overwatch.file_tree.state")
      for i = 3, line_count - 1 do
        local n = tree_state.line_to_node[i]
        if n and not n.is_dir then
          first_node = n
          break
        end
      end
      if first_node then
        actions.open_file_node(first_node)
      end
    end

    return true
  end

  -- Tree window doesn't exist, create it
  local tree_buf = M.create_file_tree_buffer(file_path, diff_only, commit_hash)
  if not tree_buf then
    return false
  end -- Exit if buffer creation failed

  -- Create new window for tree with min width (will be resized after content loads)
  local min_width = config.values.file_tree.width.min
  vim.cmd("topleft " .. min_width .. "vsplit")
  local tree_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(tree_win, tree_buf)

  -- Set window-local options (ftplugin runs before window exists)
  vim.wo[tree_win].number = false
  vim.wo[tree_win].relativenumber = false
  vim.wo[tree_win].signcolumn = "no"

  -- Store window reference in tree state and global state
  tree_state.window = tree_win
  global_state.file_tree_win = tree_win
  global_state.file_tree_buf = tree_buf -- Keep global state updated too

  position_cursor_on_first_file(tree_buf, tree_win)
  return true
end

-- Show files changed in a specific historical commit (history mode)
-- @param commit_hash string - the commit to show
-- @param parent_hash string|nil - parent commit (nil for root commits)
function M.show_history_commit(commit_hash, parent_hash)
  local tree_state = require("overwatch.file_tree.state")
  local file_path = vim.fn.getcwd()
  local diff_only = true

  -- Check if tree window already exists and is valid
  if
    tree_state.window
    and vim.api.nvim_win_is_valid(tree_state.window)
    and tree_state.buffer
    and vim.api.nvim_buf_is_valid(tree_state.buffer)
  then
    -- Reuse existing buffer and window
    local tree = FileTree.new(file_path)
    local buf = tree_state.buffer

    -- Update git status with parent-commit diff
    tree:update_git_status(file_path, diff_only, commit_hash, function()
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        render.render_tree(tree, buf)

        local win = tree_state.window
        if not win or not vim.api.nvim_win_is_valid(win) then
          return
        end

        -- Position cursor on first file
        position_cursor_on_first_file(buf, win)

        -- Auto-open first file
        local first_node
        local line_count = vim.api.nvim_buf_line_count(buf)
        for i = 3, line_count - 1 do
          local n = tree_state.line_to_node[i]
          if n and not n.is_dir then
            first_node = n
            break
          end
        end
        if first_node then
          actions.open_file_node(first_node)
        end

        -- Resize window to fit content
        local width_config = config.values.file_tree.width
        local screen_width = vim.o.columns
        local max_width = math.floor(screen_width * width_config.max_percent / 100)
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local max_line_width = 0
        for _, line in ipairs(lines) do
          local display_width = vim.fn.strdisplaywidth(line)
          if display_width > max_line_width then
            max_line_width = display_width
          end
        end
        local optimal_width = math.max(width_config.min, math.min(max_line_width + width_config.padding, max_width))
        vim.api.nvim_win_set_width(win, optimal_width)
      end)
    end, parent_hash)

    return true
  end

  -- Tree window doesn't exist, create it
  return M.show(commit_hash)
end

-- Expose actions for keymaps setup elsewhere if needed (though direct require is preferred)
M.actions = actions

return M
