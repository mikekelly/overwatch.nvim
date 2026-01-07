-- hunk_view.lua - Display diff hunks for historical commits
local M = {}

local Job = require("overwatch.utils.job")

M.hunk_buf = nil

-- Create or get the hunk view buffer
function M.get_or_create_buffer()
  if M.hunk_buf and vim.api.nvim_buf_is_valid(M.hunk_buf) then
    return M.hunk_buf
  end

  M.hunk_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.hunk_buf].buftype = "nofile"
  vim.bo[M.hunk_buf].swapfile = false
  vim.bo[M.hunk_buf].bufhidden = "hide"
  vim.bo[M.hunk_buf].filetype = "overwatch_hunk"

  return M.hunk_buf
end

-- Display diff hunks for a file between two commits
-- @param file_path string - relative path to the file
-- @param commit string - the commit to show
-- @param parent_commit string|nil - parent commit (nil for root commit)
function M.show(file_path, commit, parent_commit)
  local global_state = require("overwatch.state")
  local buf = M.get_or_create_buffer()
  local cwd = vim.fn.getcwd()

  -- Build git diff command
  local diff_args
  if parent_commit then
    diff_args = { "git", "diff", parent_commit, commit, "--", file_path }
  else
    -- Root commit: diff against empty tree
    -- 4b825dc642cb6eb9a060e54bf8d69288fbee4904 is the empty tree hash
    diff_args = { "git", "diff", "4b825dc642cb6eb9a060e54bf8d69288fbee4904", commit, "--", file_path }
  end

  Job.run(diff_args, { cwd = cwd }, function(out, code, _)
    vim.schedule(function()
      if code ~= 0 and code ~= 1 then
        vim.api.nvim_echo({ { "Failed to get diff", "ErrorMsg" } }, false, {})
        return
      end

      M.render_diff(buf, out, file_path, commit)
      M.show_in_window(buf)
    end)
  end)
end

-- Render diff output with syntax highlighting
function M.render_diff(buf, diff_output, file_path, commit)
  local lines = vim.split(diff_output, "\n")
  local display_lines = {}
  local highlights = {} -- { line_num (0-based), hl_group }

  -- Header
  table.insert(display_lines, "File: " .. file_path)
  table.insert(display_lines, "Commit: " .. commit:sub(1, 8))
  table.insert(display_lines, string.rep("─", 60))
  table.insert(display_lines, "")

  -- Track header line count for highlight offset
  local header_offset = #display_lines

  for _, line in ipairs(lines) do
    -- Skip file headers (diff, index, ---, +++ lines)
    if
      not line:match("^diff ")
      and not line:match("^index ")
      and not line:match("^%-%-%-")
      and not line:match("^%+%+%+")
    then
      local line_num = #display_lines
      table.insert(display_lines, line)

      -- Track highlights based on line prefix
      if line:match("^@@") then
        table.insert(highlights, { line = line_num, hl = "Function" })
      elseif line:match("^%+") then
        table.insert(highlights, { line = line_num, hl = "DiffAdd" })
      elseif line:match("^%-") then
        table.insert(highlights, { line = line_num, hl = "DiffDelete" })
      end
    end
  end

  -- Handle empty diff (file was added but empty, or binary, etc.)
  if #display_lines == header_offset then
    table.insert(display_lines, "(No diff content)")
  end

  -- Set buffer content
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
  vim.bo[buf].modifiable = false

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("overwatch_hunk_view")
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  -- Highlight header
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Comment", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns_id, "NonText", 2, 0, -1)

  -- Highlight diff lines
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns_id, hl.hl, hl.line, 0, -1)
  end
end

-- Show buffer in main window
function M.show_in_window(buf)
  local global_state = require("overwatch.state")
  local tree_win = require("overwatch.file_tree.state").window
  local win = global_state.get_main_window()

  if not win or not vim.api.nvim_win_is_valid(win) or win == tree_win then
    -- Create a new window to the right of the tree
    vim.cmd("rightbelow vsplit")
    win = vim.api.nvim_get_current_win()
    global_state.main_win = win
  end

  vim.api.nvim_win_set_buf(win, buf)

  -- Move cursor to first hunk
  local line_count = vim.api.nvim_buf_line_count(buf)
  for i = 4, line_count do -- Start after header
    local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
    if line and line:match("^@@") then
      vim.api.nvim_win_set_cursor(win, { i, 0 })
      break
    end
  end
end

-- Clear the hunk view buffer
function M.clear()
  if M.hunk_buf and vim.api.nvim_buf_is_valid(M.hunk_buf) then
    vim.api.nvim_buf_delete(M.hunk_buf, { force = true })
  end
  M.hunk_buf = nil
end

return M
