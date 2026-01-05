-- Module for rendering the FileTree structure into a Neovim buffer
local tree_state = require("overwatch.file_tree.state")

local M = {}

-- Helper: Shorten directory path for display
-- Input: "lua/overwatch/file_tree/render.lua" -> Output: { "l/u/f/file_tree", "render.lua" }
-- Input: "README.md" -> Output: { "", "README.md" }
local function get_shortened_display_parts(full_path)
  local parts = {}
  for part in string.gmatch(full_path, "[^/]+") do
    table.insert(parts, part)
  end

  if #parts == 0 then
    return { "", "" } -- Should not happen with valid paths
  elseif #parts == 1 then
    return { "", parts[1] } -- File in root
  else
    local shortened_parts = {}
    for i = 1, #parts - 1 do
      table.insert(shortened_parts, string.sub(parts[i], 1, 1))
    end
    -- Shorten all parts except the last directory part
    local display_parts = {}
    for i = 1, #parts - 2 do -- Shorten initial parts
      table.insert(display_parts, string.sub(parts[i], 1, 1))
    end
    -- Add the last directory part fully
    table.insert(display_parts, parts[#parts - 1])

    local shortened_dir_path = table.concat(display_parts, "/")
    local filename = parts[#parts]
    return { shortened_dir_path, filename }
  end
end

-- Helper: Recursively collect file nodes, optionally filtering by status
local function collect_and_filter_files(node, filter_changed_only)
  local files = {}
  local function traverse(current_node)
    if not current_node.is_dir then
      local include_file = true
      if filter_changed_only then
        local status_to_check = current_node.status or " "
        include_file = status_to_check ~= " "
      end
      if include_file then
        table.insert(files, current_node)
      end
    elseif current_node.is_dir then
      local children = current_node:get_children() -- Assuming get_children exists
      for _, child in ipairs(children) do
        traverse(child)
      end
    end
  end
  traverse(node)
  return files
end

-- Render the file tree to a buffer with the new flattened, shortened path structure
function M.render_tree(tree, buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  local ns_id = vim.api.nvim_create_namespace("overwatch_file_tree")

  -- Create custom highlight groups (foreground only, no background)
  vim.api.nvim_set_hl(0, "OverwatchAdd", { fg = "#73daca" })
  vim.api.nvim_set_hl(0, "OverwatchDelete", { fg = "#f7768e" })

  -- Clear buffer and previous state
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {})
  tree_state.line_to_node = {} -- Reset line mapping

  -- === Header Generation (Mostly unchanged) ===
  local header_text = tree.root.path
  local home = vim.fn.expand("~")
  if header_text:sub(1, #home) == home then
    header_text = "~" .. header_text:sub(#home + 1)
  end
  header_text = header_text:gsub("^file://", "")
  if #header_text > 40 then
    local components = {}
    for part in header_text:gmatch("([^/]+)") do
      table.insert(components, part)
    end
    if #components > 3 then
      header_text = "~/"
        .. table.concat({ components[#components - 2], components[#components - 1], components[#components] }, "/")
    end
  end

  local header_lines = {
    "  " .. header_text,
  }

  -- === Collect, Filter, Group, and Sort Files ===
  local all_files = collect_and_filter_files(tree.root, tree_state.diff_only)
  local grouped_files = {}
  local group_keys = {} -- To store unique shortened paths for sorting
  local root_path = tree.root.path
  local root_path_len = #root_path

  for _, file_node in ipairs(all_files) do
    -- Calculate path relative to the root
    local relative_path = file_node.path
    if relative_path:sub(1, root_path_len) == root_path then
      relative_path = relative_path:sub(root_path_len + 1)
      -- Remove leading slash if present after stripping root
      if relative_path:sub(1, 1) == "/" then
        relative_path = relative_path:sub(2)
      end
    end

    local parts = get_shortened_display_parts(relative_path)
    local shortened_path = parts[1]
    local filename = parts[2]

    if not grouped_files[shortened_path] then
      grouped_files[shortened_path] = {}
      table.insert(group_keys, shortened_path) -- Add new key for sorting
    end
    table.insert(grouped_files[shortened_path], { name = filename, node = file_node })
  end

  -- Sort group keys (shortened paths) alphabetically, root ("") first
  table.sort(group_keys)

  -- Sort files within each group alphabetically by filename
  for key, files_in_group in pairs(grouped_files) do
    table.sort(files_in_group, function(a, b)
      return a.name < b.name
    end)
  end

  -- === Determine Repository Status Line ===
  local has_git_dir = vim.fn.isdirectory(tree.root.path .. "/.git") == 1
  local status_line = ""
  if has_git_dir then
    local changed_count = 0
    for _, file_node in ipairs(collect_and_filter_files(tree.root, true)) do -- Count all changed files
      changed_count = changed_count + 1
    end

    if changed_count > 0 then
      status_line = "  Changes: " .. changed_count
    elseif not tree_state.diff_only then
      status_line = "  No changes"
    end
    -- "No changes to display" handled later if grouped_files is empty in diff_only mode
  else
    if #all_files > 0 then -- Check if any files exist at all
      status_line = "  Directory View"
    else
      status_line = "  Empty Directory"
    end
  end
  if status_line ~= "" then
    table.insert(header_lines, status_line)
    table.insert(header_lines, "") -- gap before files
  else
    table.insert(header_lines, "") -- gap before files
  end

  -- === Render Lines ===
  local lines = vim.list_extend({}, header_lines) -- Start with header
  local highlights = {}
  local current_line = #lines - 1 -- 0-based index for buffer lines

  for group_idx, shortened_path in ipairs(group_keys) do
    local files_in_group = grouped_files[shortened_path]
    local is_root_group = (shortened_path == "")

    -- Render Path Header (if not root)
    if not is_root_group then
      current_line = current_line + 1
      table.insert(lines, "  " .. shortened_path)
      table.insert(highlights, {
        line = current_line,
        col = 2, -- Start after initial indent
        length = #shortened_path,
        hl_group = "Directory",
      })
      tree_state.line_to_node[current_line] = nil -- Not a selectable node
    end

    -- Render Files in Group
    for file_idx, file_info in ipairs(files_in_group) do
      current_line = current_line + 1
      local node = file_info.node
      local indent = is_root_group and "" or "  " -- Indent files under path headers

      -- Format status indicator
      local status_char = " "
      local status_hl = nil
      if node.status and node.status:match("[?]") then
        status_char = "+" -- new/untracked
        status_hl = "OverwatchAdd"
      elseif node.status and node.status:match("[A]") then
        status_char = "+" -- added/staged
        status_hl = "OverwatchAdd"
      elseif node.status and node.status:match("[M]") then
        status_char = "󰏫" -- modified (white, no highlight)
        status_hl = nil
      elseif node.status and node.status:match("[D]") then
        status_char = "−" -- deleted (minus sign)
        status_hl = "OverwatchDelete"
      elseif node.status and node.status:match("[R]") then
        status_char = "→" -- renamed
        status_hl = nil
      elseif node.status and node.status:match("[C]") then
        status_char = "✓" -- committed
        status_hl = "Comment"
      end

      -- Format line with status icon inline
      local line_text = "  " .. indent .. status_char .. " " .. file_info.name
      table.insert(lines, line_text)

      -- Map line to node
      tree_state.line_to_node[current_line] = node

      -- Apply highlight to status icon only
      if status_hl then
        local status_start_col = 2 + #indent
        table.insert(highlights, {
          line = current_line,
          col = status_start_col,
          length = #status_char,
          hl_group = status_hl,
        })
      end
    end
  end

  -- Add "No changes" only if in diff_only mode and no files were found
  if tree_state.diff_only and #all_files == 0 and status_line == "" then
    table.insert(lines, "  No changes")
    current_line = current_line + 1
  end

  -- === Render Submodules with Changes ===
  local submodules = tree_state.submodules or {}
  for _, submodule in ipairs(submodules) do
    -- Add separator
    current_line = current_line + 1
    table.insert(lines, "")

    -- Submodule header with icon
    local sub_header = "   " .. submodule.path -- nf-cod-folder_library
    local sub_status_text = ""
    if submodule.status == "+" then
      sub_status_text = " (HEAD differs)"
    elseif submodule.status == "-" then
      sub_status_text = " (not initialized)"
    elseif submodule.status == "U" then
      sub_status_text = " (conflicts)"
    end
    sub_header = sub_header .. sub_status_text

    current_line = current_line + 1
    table.insert(lines, sub_header)
    table.insert(highlights, {
      line = current_line,
      col = 0,
      length = #sub_header,
      hl_group = "Directory",
    })

    -- Changes count for submodule
    local sub_changed_files = submodule.changed_files or {}
    local sub_change_count = 0
    for _ in pairs(sub_changed_files) do
      sub_change_count = sub_change_count + 1
    end

    if sub_change_count > 0 then
      current_line = current_line + 1
      local sub_changes_line = "  Changes: " .. sub_change_count
      table.insert(lines, sub_changes_line)
      table.insert(highlights, {
        line = current_line,
        col = 0,
        length = #sub_changes_line,
        hl_group = "WarningMsg",
      })

      -- Gap before files
      current_line = current_line + 1
      table.insert(lines, "")

      -- Collect and sort submodule files
      local sub_files = {}
      local sub_root = tree.root.path .. "/" .. submodule.path
      local sub_root_len = #sub_root

      for file_path, file_status in pairs(sub_changed_files) do
        local rel_path = file_path
        if rel_path:sub(1, sub_root_len) == sub_root then
          rel_path = rel_path:sub(sub_root_len + 1)
          if rel_path:sub(1, 1) == "/" then
            rel_path = rel_path:sub(2)
          end
        end
        table.insert(sub_files, {
          path = file_path,
          rel_path = rel_path,
          status = file_status,
        })
      end

      table.sort(sub_files, function(a, b)
        return a.rel_path < b.rel_path
      end)

      -- Render submodule files
      for _, file_info in ipairs(sub_files) do
        current_line = current_line + 1
        local display_name = file_info.rel_path

        -- Shorten long paths
        local parts = get_shortened_display_parts(display_name)
        if parts[1] ~= "" then
          display_name = parts[1] .. "/" .. parts[2]
        else
          display_name = parts[2]
        end

        -- Format status indicator
        local status_char = " "
        local status_hl = nil
        if file_info.status and file_info.status:match("[?]") then
          status_char = "+" -- new/untracked
          status_hl = "OverwatchAdd"
        elseif file_info.status and file_info.status:match("[A]") then
          status_char = "+" -- added/staged
          status_hl = "OverwatchAdd"
        elseif file_info.status and file_info.status:match("[M]") then
          status_char = "󰏫" -- modified (white, no highlight)
          status_hl = nil
        elseif file_info.status and file_info.status:match("[D]") then
          status_char = "−" -- deleted (minus sign)
          status_hl = "OverwatchDelete"
        elseif file_info.status and file_info.status:match("[R]") then
          status_char = "→" -- renamed
          status_hl = nil
        end

        local line_text = "  " .. status_char .. " " .. display_name
        table.insert(lines, line_text)

        -- Create a pseudo-node for the submodule file
        local Node = require("overwatch.file_tree.node")
        local sub_file_node = Node.new(display_name, false)
        sub_file_node.path = file_info.path
        sub_file_node.status = file_info.status
        sub_file_node.is_submodule_file = true
        sub_file_node.submodule_path = submodule.path
        tree_state.line_to_node[current_line] = sub_file_node

        -- Apply highlight to status icon only
        if status_hl then
          table.insert(highlights, {
            line = current_line,
            col = 2,
            length = #status_char,
            hl_group = status_hl,
          })
        end
      end
    elseif submodule.status == "+" then
      -- HEAD differs but no dirty files - just show the header
      current_line = current_line + 1
      table.insert(lines, "")
    end
  end

  -- === Final Buffer Operations ===
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

  -- Apply text highlights
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buffer, ns_id, hl.hl_group, hl.line, hl.col, hl.col + hl.length)
  end

  -- Add highlighting for the main header
  vim.api.nvim_buf_add_highlight(buffer, ns_id, "Title", 0, 0, -1) -- Header path

  -- Add highlighting for repository status line (line 1, 0-based)
  local status_line_content = lines[2] -- 1-based index
  if status_line_content then
    if status_line_content:match("Changes: %d") then
      vim.api.nvim_buf_add_highlight(buffer, ns_id, "WarningMsg", 1, 0, -1)
    elseif
      status_line_content:match("No changes")
      or status_line_content:match("Directory View")
      or status_line_content:match("Empty Directory")
    then
      vim.api.nvim_buf_add_highlight(buffer, ns_id, "Comment", 1, 0, -1)
    end
  end

  -- Set buffer as non-modifiable
  vim.bo[buffer].modifiable = false

  -- Update tree state references
  tree_state.buffer = buffer
  tree_state.current_tree = tree
end

return M
