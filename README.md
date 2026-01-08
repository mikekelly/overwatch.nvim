# overwatch.nvim

A Neovim plugin for copiloting with AI coding agents. Provides a real-time UI for reviewing unstaged changes as they happen, plus the ability to browse through commit history—all without leaving the editor.

![Overwatch demo](demo.gif)

Fork of [unified.nvim](https://github.com/axkirillov/unified.nvim) with enhanced file tree navigation.

## Features

* **Inline Diffs**: View git diffs directly in your buffer, without needing a separate window.
* **File Tree Explorer**: A file tree explorer showing changed files with status icons.
* **History Navigation**: Browse commit history with `h`/`l` keys to see what changed in previous commits.
* **Hunk Actions**: Stage, unstage, or revert individual hunks without leaving the editor.
* **Auto-preview on Navigation**: Moving through files in the tree automatically previews the diff.
* **Auto-refresh**: Both the file tree and diff view automatically refresh when changes are detected.
* **Submodule Support**: Optionally display changed files in git submodules.
* **Git Gutter Signs**: Gutter signs indicate added, modified, and deleted lines.
* **Cursor Line Highlighting**: Grey background highlights the selected line in the file tree.
* **Customizable**: Configure signs, highlights, and line symbols to your liking.

## What's Different from unified.nvim?

1. **Auto-preview**: `j`/`k` navigation in the file tree automatically opens and previews the file diff
2. **History navigation**: Browse through commit history with `h`/`l` keys directly from the file tree
3. **Auto-refresh file tree**: The file tree polls git status and refreshes when changes are detected
4. **Submodule support**: Optionally shows changed files within git submodules
5. **Hunk actions**: Stage, unstage, or revert individual hunks via API
6. **Improved status icons**: Uses visual icons (`+`, `󰏫`, `−`) instead of letters for file status
7. **Enter to focus**: Press `<CR>` to open a file and move cursor into the main buffer
8. **Cursor line highlighting**: Selected line in file tree has grey background for visibility

## Requirements

-   Neovim >= 0.10.0
-   Git
-   A [Nerd Font](https://www.nerdfonts.com/) installed and configured in your terminal/GUI is required to display file icons correctly in the file tree.

## Installation

You can install `overwatch.nvim` using your favorite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'mikekelly/overwatch.nvim',
  opts = {
    -- your configuration comes here
  }
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'mikekelly/overwatch.nvim',
  config = function()
    require('overwatch').setup({
      -- your configuration comes here
    })
  end
}
```

## Configuration

You can configure `overwatch.nvim` by passing a table to the `setup()` function. Here are the default settings:

```lua
require('overwatch').setup({
  signs = {
    add = "│",
    delete = "│",
    change = "│",
  },
  highlights = {
    add = "DiffAdd",
    delete = "DiffDelete",
    change = "DiffChange",
  },
  line_symbols = {
    add = "+",
    delete = "-",
    change = "~",
  },
  auto_refresh = true, -- Whether to automatically refresh diff when buffer changes
  file_tree = {
    auto_refresh = true, -- Whether to auto-refresh file tree when git status changes
    refresh_interval = 2000, -- Polling interval in milliseconds
    width = {
      min = 30, -- Minimum width in columns
      max_percent = 40, -- Maximum width as percentage of screen width
      padding = 2, -- Extra padding added to content width
    },
    submodules = {
      enabled = false, -- Set to true to show changed files in submodules
    },
  },
})
```

## Usage

1.  Open a file in a git repository.
2.  Make some changes to the file.
3.  Run the command `:Overwatch` to display the diff against `HEAD` and open the file tree.
4.  To close the diff view and file tree, run `:Overwatch` again.
5.  To show the diff against a specific commit, run `:Overwatch <commit_ref>`, for example `:Overwatch HEAD~1`.

### File Tree Interaction

When the file tree is open, you can use the following keymaps:

| Key | Action |
|-----|--------|
| `j`/`k` or `↓`/`↑` | Move between files and **automatically preview** the diff |
| `<CR>` (Enter) | Open the file and **move cursor into the main buffer** |
| `l` | Open the file under cursor (keeps focus in tree), or navigate forward in history |
| `h` | Navigate back through commit history |
| `q` | Close the file tree window |
| `R` | Manually refresh the file tree |
| `?` | Show a help dialog |

When the file tree opens, the first file is automatically opened in the main window.

### History Navigation

Overwatch lets you browse through commit history directly from the file tree:

1. Press `h` to go back in time — view files changed in older commits
2. Press `l` to go forward — return to more recent commits
3. When you reach the most recent point, `l` exits history mode and returns to the working tree

This is useful for reviewing what changed in previous commits without leaving the editor.

The file tree displays the Git status of each file with icons:

  - `+` (green): Added or untracked
  - `󰏫` (white): Modified
  - `−` (red): Deleted
  - `→`: Renamed
  - `✓` (grey): Committed

### Navigating Hunks

To navigate between hunks, you'll need to set your own keymaps:

```lua
vim.keymap.set('n', ']h', function() require('overwatch.navigation').next_hunk() end)
vim.keymap.set('n', '[h', function() require('overwatch.navigation').previous_hunk() end)
```

### Toggle API

For programmatic control, you can use the toggle function:

```lua
vim.keymap.set('n', '<leader>ud', require('overwatch').toggle, { desc = 'Toggle overwatch diff' })
```

This toggles the diff view on/off, remembering the previous commit reference.

### Hunk actions (API)

Overwatch provides a function-only API for hunk actions. Define your own keymaps or commands if desired.

Example keymaps:

```lua
local actions = require('overwatch.hunk_actions')
vim.keymap.set('n', 'gs', actions.stage_hunk,   { desc = 'Overwatch: Stage hunk' })
vim.keymap.set('n', 'gu', actions.unstage_hunk, { desc = 'Overwatch: Unstage hunk' })
vim.keymap.set('n', 'gr', actions.revert_hunk,  { desc = 'Overwatch: Revert hunk' })
```

Behavior notes:
- Operates on the hunk under the cursor inside a regular file buffer (not in the overwatch file tree buffer).
- Stage: applies a minimal single-hunk patch to the index.
- Unstage: reverse-applies the hunk patch from the index.
- Revert: reverse-applies the hunk patch to the working tree.
- Binary patches are skipped with a user message.
- After an action, the inline diff and file tree are refreshed automatically.

## Commands

  * `:Overwatch`: Toggles the diff view. If closed, it shows the diff against `HEAD`. If open, it closes the view.
  * `:Overwatch <commit_ref>`: Shows the diff against the specified commit reference (e.g., a commit hash, branch name, or tag) and opens the file tree for that range.
  * `:Overwatch reset`: Removes all overwatch diff highlights and signs from the current buffer and closes the file tree window if it is open.

## Development

### Running Tests

To run all automated tests:

```bash
make tests
```

To run a specific test function:

```bash
make test TEST=test_file_name.test_function_name
```

## License

MIT
