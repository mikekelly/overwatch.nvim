local M = {}

local function is_file_tree_buffer()
  local state = require("overwatch.file_tree.state")
  return vim.api.nvim_get_current_buf() == state.buffer
end

local function open_file_node(node)
  if not node or node.is_dir then
    return
  end

  local state = require("overwatch.state")
  local tree_win = vim.api.nvim_get_current_win()
  local win = state.get_main_window()

  if not win or not vim.api.nvim_win_is_valid(win) or win == tree_win then
    vim.cmd("rightbelow vsplit")
    win = vim.api.nvim_get_current_win()
    state.main_win = win
    -- Restore focus to the tree window so the cursor does not jump
    if vim.api.nvim_win_is_valid(tree_win) then
      vim.api.nvim_set_current_win(tree_win)
    end
  end

  -- Open the target buffer in the main window without changing focus
  local target_path = vim.fn.fnameescape(node.path)
  local target_buf_id = vim.fn.bufadd(target_path)

  -- If bufload fails (e.g., swap file E325), open normally to trigger Neovim's swap resolution UI
  local ok, _ = pcall(vim.fn.bufload, target_buf_id)
  if not ok then
    vim.api.nvim_set_current_win(win)
    vim.cmd("edit " .. target_path)
    return
  end

  if not vim.api.nvim_buf_is_valid(target_buf_id) then
    vim.api.nvim_echo({ { "Failed to load buffer for: " .. node.path, "ErrorMsg" } }, false, {})
    return
  end
  vim.api.nvim_win_set_buf(win, target_buf_id)

  local diff = require("overwatch.diff")
  local commit = state.get_commit_base()
  diff.show(commit, target_buf_id)
  local auto_refresh = require("overwatch.auto_refresh")
  auto_refresh.setup(target_buf_id)

  -- Scroll opened buffer to first git hunk without changing focus (diffview-like)
  local hunk_store = require("overwatch.hunk_store")
  local hunks = hunk_store.get(target_buf_id)
  if hunks and #hunks > 0 then
    local first = hunks[1]
    local line_count = vim.api.nvim_buf_line_count(target_buf_id)
    if first > line_count then
      first = line_count
    end
    if vim.api.nvim_win_is_valid(win) then
      -- Move the other window's cursor
      pcall(vim.api.nvim_win_set_cursor, win, { first, 0 })
      -- Center the view in that window, without stealing focus
      pcall(vim.api.nvim_win_call, win, function()
        vim.cmd.normal({ "zz", bang = true })
      end)
    end
  end
end

-- Open file under cursor (previously toggle_node)
function M.toggle_node()
  if not is_file_tree_buffer() then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local state = require("overwatch.file_tree.state")
  local node = state.line_to_node[line]

  if not node then
    return
  end

  -- Call the helper function to open the file
  open_file_node(node)
end

function M.refresh(force)
  -- Skip buffer check if force=true (e.g., from auto-refresh)
  if not force and not is_file_tree_buffer() then
    return
  end

  local tree_state = require("overwatch.file_tree.state")
  local root_path = tree_state.root_path
  local diff_only = tree_state.diff_only
  local commit_ref = tree_state.commit_ref
  local buf = tree_state.buffer
  local win = tree_state.window

  local FileTree = require("overwatch.file_tree.tree")
  local render = require("overwatch.file_tree.render")

  local tree = FileTree.new(root_path)

  local function after_render()
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
      return
    end

    local first_line, first_node
    for l = 3, vim.api.nvim_buf_line_count(buf) - 1 do
      local n = tree_state.line_to_node[l]
      if n and not n.is_dir then
        first_line, first_node = l, n
        break
      end
    end

    if first_node then
      vim.api.nvim_win_set_cursor(win, { first_line + 1, 0 })
    end

    -- Resize window to fit content
    local config = require("overwatch.config")
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
  end

  local function do_render()
    render.render_tree(tree, buf)
    vim.schedule(after_render)
  end

  local function finish(ok)
    if not ok then
      return
    end

    -- Fetch submodules if enabled
    local config = require("overwatch.config")
    local submodules_config = config.values.file_tree.submodules or {}
    if submodules_config.enabled then
      local submodule_utils = require("overwatch.utils.submodule")
      submodule_utils.get_changed_submodules(root_path, function(submodules)
        tree_state.submodules = submodules or {}
        do_render()
      end)
    else
      tree_state.submodules = {}
      do_render()
    end
  end

  tree:update_git_status(root_path, diff_only, commit_ref, finish)
end

-- Show help dialog
function M.show_help()
  if not is_file_tree_buffer() then
    return
  end

  local help_text = {
    "Overwatch File Explorer Help",
    "------------------------",
    "",
    "Navigation:",
    "  j/k       : Move up/down",
    "",
    "Actions:",
    "  R         : Refresh the tree",
    "  q         : Close the tree",
    "  ?         : Show this help",
    "",
    "File Status:",
    "  M         : Modified",
    "  A         : Added",
    "  D         : Deleted",
    "  R         : Renamed",
    "  C         : Copied / In Commit",
    "  ?         : Untracked",
    "",
    "Press any key to close this help",
  }

  -- Create a temporary floating window
  local win_width = math.max(40, math.floor(vim.o.columns / 3))
  local win_height = #help_text

  local win_opts = {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = math.floor((vim.o.lines - win_height) / 2),
    col = math.floor((vim.o.columns - win_width) / 2),
    style = "minimal",
    border = "rounded",
  }

  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_text)

  local _ = vim.api.nvim_open_win(help_buf, true, win_opts)

  -- Set buffer options
  vim.bo[help_buf].modifiable = false
  vim.bo[help_buf].bufhidden = "wipe"

  -- Add highlighting
  local ns_id = vim.api.nvim_create_namespace("overwatch_help")
  vim.api.nvim_buf_add_highlight(help_buf, ns_id, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(help_buf, ns_id, "NonText", 1, 0, -1)

  -- Highlight section headers
  for i, line in ipairs(help_text) do
    if line:match("^[A-Za-z]") and line:match(":$") then
      vim.api.nvim_buf_add_highlight(help_buf, ns_id, "Statement", i - 1, 0, -1)
    end
    -- Highlight keys
    if line:match("^  [^:]+:") then
      local key_end = line:find(":")
      if key_end then
        vim.api.nvim_buf_add_highlight(help_buf, ns_id, "Special", i - 1, 2, key_end)
      end
    end
  end

  -- Close on any key press
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<Space>", "<cmd>close<CR>", { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(help_buf, "n", "q", "<cmd>close<CR>", { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<CR>", "<cmd>close<CR>", { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<Esc>", "<cmd>close<CR>", { silent = true, noremap = true })
end

-- Go to parent directory node
function M.go_to_parent()
  if not is_file_tree_buffer() then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local state = require("overwatch.file_tree.state")
  local node = state.line_to_node[line]

  if not node or not node.parent or node.parent == state.current_tree.root then
    -- Don't go above the root shown in the tree
    return
  end

  -- Find the parent node's line
  local parent_line = nil
  for l, n in pairs(state.line_to_node) do
    if n == node.parent then
      parent_line = l
      break
    end
  end

  if parent_line then
    vim.api.nvim_win_set_cursor(0, { parent_line + 1, 0 })
  end
end

-- Close the file tree window
function M.close_tree()
  -- Stop auto-refresh timer
  local tree_auto_refresh = require("overwatch.file_tree.auto_refresh")
  tree_auto_refresh.stop()

  local state = require("overwatch.file_tree.state")
  if state.window and vim.api.nvim_win_is_valid(state.window) then
    vim.api.nvim_win_close(state.window, true)
  end
  -- Reset state after closing
  state.reset_state()
  -- Also reset the global active state if the main plugin relies on the tree being open
  local global_state = require("overwatch.state")
  global_state.file_tree_win = nil
  global_state.file_tree_buf = nil
end -- End of M.close_tree

-- Move cursor to the next/previous file node and open it
function M.move_cursor_and_open_file(direction)
  if not is_file_tree_buffer() then
    return
  end

  local current_line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
  local state = require("overwatch.file_tree.state")
  local total_lines = vim.api.nvim_buf_line_count(state.buffer)
  local next_line = current_line

  for _ = 1, total_lines do -- Iterate at most total_lines times
    next_line = (next_line + direction + total_lines) % total_lines -- Wrap around

    local node = state.line_to_node[next_line]
    if node and not node.is_dir then
      -- Found the next file node
      vim.api.nvim_win_set_cursor(0, { next_line + 1, 0 }) -- Set cursor (1-based)
      open_file_node(node) -- Open the file
      return -- Done
    end
  end
  -- If no file node found after full loop (unlikely in a populated tree), do nothing
end -- End of M.move_cursor_and_open_file

-- Move cursor within the file tree to file nodes only
-- direction: 1 (down/next) or -1 (up/previous)
-- count: optional repeat count; defaults to 1
function M.move_cursor_file_only(direction, count)
  if not is_file_tree_buffer() then
    return
  end

  local tree_state = require("overwatch.file_tree.state")
  if not tree_state.buffer or not vim.api.nvim_buf_is_valid(tree_state.buffer) then
    return
  end

  local total_lines = vim.api.nvim_buf_line_count(tree_state.buffer)
  if not total_lines or total_lines < 1 then
    return
  end

  direction = direction or 1
  if direction == 0 then
    return
  end
  count = count or 1

  local current_line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
  for _ = 1, count do
    local next_line = current_line
    for _i = 1, total_lines do
      next_line = (next_line + direction + total_lines) % total_lines
      local node = tree_state.line_to_node[next_line]
      if node and not node.is_dir then
        current_line = next_line
        break
      end
    end
  end

  vim.api.nvim_win_set_cursor(0, { current_line + 1, 0 })
end

-- Open file under cursor and move focus to the buffer
function M.open_and_focus()
  if not is_file_tree_buffer() then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local state = require("overwatch.file_tree.state")
  local node = state.line_to_node[line]

  if not node or node.is_dir then
    return
  end

  -- Open the file first (this keeps focus in tree)
  open_file_node(node)

  -- Now move focus to the main window
  local global_state = require("overwatch.state")
  local win = global_state.get_main_window()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

M.open_file_node = open_file_node -- Expose for use in init.lua

return M
