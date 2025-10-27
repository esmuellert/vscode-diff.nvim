# Neo-tree Flexibility Analysis

## TL;DR - Critical Findings

**Question:** Can Neo-tree compare any two git commits with full customization?

**Answer:** 
- ❌ **Built-in `git_status`** - NO, only compares working directory vs HEAD/branch
- ✅ **Custom Source** - YES, FULLY customizable! You can do ANYTHING.

## Built-in git_status Limitations

### What it CAN do:
```vim
:Neotree git_status                    " Working dir vs HEAD
:Neotree git_status git_base=main      " Working dir vs main branch
:Neotree git_status git_base=HEAD~1    " Working dir vs HEAD~1
```

### What it CANNOT do:
- ❌ Compare two arbitrary commits (e.g., `abc123` vs `def456`)
- ❌ Show diff stats inline
- ❌ Custom filtering
- ❌ Integration with your C diff engine

### Why?
Looking at the code (`lua/neo-tree/git/status.lua`):

```lua
-- Built-in uses these git commands:
git diff --staged --name-status <base> --
git diff --name-status                    -- unstaged changes
git ls-files --exclude-standard --others  -- untracked files
```

It's designed to show **working directory status**, not arbitrary commit comparisons.

## Custom Source - FULL FLEXIBILITY ✅

### Neo-tree's Source System is Extremely Flexible

You can create a **completely custom source** with:
- Full control over git commands
- Custom data retrieval (any git comparison)
- Custom rendering
- Custom components
- Custom filtering/sorting
- Integration with your C diff engine

### Source API Structure

```lua
-- Location: lua/neo-tree/sources/vscode_diff/init.lua
local M = {
  name = "vscode_diff",           -- Required
  display_name = " 󰊢 VSCode Diff ", -- Required
}

-- FULL CONTROL HERE
function M.navigate(state, path, path_to_reveal, callback, async)
  -- 1. Get ANY data you want
  -- 2. Build tree structure YOUR way
  -- 3. Call YOUR C diff engine
  -- 4. Show YOUR custom components
end

function M.setup(config, global_config)
  -- Configure YOUR source
  -- Subscribe to events
  -- Setup YOUR custom settings
end

return M
```

### Example: Compare ANY Two Commits

```lua
-- Custom function using git diff
local function get_files_between_commits(commit1, commit2, cwd)
  local result = vim.system({
    "git",
    "diff",
    "--name-status",  -- M, A, D status
    commit1,
    commit2
  }, { cwd = cwd, text = true }):wait()
  
  if result.code ~= 0 then
    return {}
  end
  
  local files = {}
  for _, line in ipairs(vim.split(result.stdout, "\n")) do
    if line ~= "" then
      local status, path = line:match("^(%S+)%s+(.+)$")
      if status and path then
        files[path] = status
      end
    end
  end
  
  return files
end

function M.navigate(state, path, path_to_reveal, callback, async)
  -- Get custom parameters from user
  local commit1 = state.commit1 or "HEAD~1"
  local commit2 = state.commit2 or "HEAD"
  
  -- Get files YOUR way
  local status_lookup = get_files_between_commits(commit1, commit2, state.path)
  
  -- Build tree and render
  -- (see full example below)
end
```

### Usage Examples

```vim
" Compare any two commits
:Neotree vscode_diff commit1=HEAD~5 commit2=HEAD
:Neotree vscode_diff commit1=main commit2=feature-branch
:Neotree vscode_diff commit1=abc123 commit2=def456

" Floating window
:Neotree float vscode_diff commit1=v1.0.0 commit2=v2.0.0
```

## Advanced Customization Possibilities

### 1. Custom Components (Show Diff Stats)

You can create custom components to show:
- Number of additions/deletions
- File size changes
- Your C diff engine results
- Any custom data

```lua
-- lua/neo-tree/sources/vscode_diff/components.lua
local M = {}

M.diff_stats = function(config, node, state)
  if node.type ~= "file" then
    return {}
  end
  
  -- Get diff stats using YOUR C diff engine
  local stats = get_diff_stats(node.path, state.commit1, state.commit2)
  
  return {
    text = string.format("+%d -%d", stats.additions, stats.deletions),
    highlight = "DiffAdd",
  }
end

return M
```

Then use it in your renderer:

```lua
-- In your source setup
window = {
  mappings = {
    -- Custom keybindings
    ["<CR>"] = function(state)
      local node = state.tree:get_node()
      -- Open in vscode-diff
      vim.cmd("VscodeDiff " .. state.commit1)
    end,
  }
},
renderers = {
  file = {
    { "icon" },
    { "name", use_git_status_colors = true },
    { "diff_stats" },  -- YOUR custom component
    { "git_status" },
  },
}
```

### 2. Integration with Your C Diff Engine

```lua
function M.navigate(state, path, path_to_reveal, callback, async)
  local files = get_files_between_commits(commit1, commit2, state.path)
  
  -- For each file, compute diff stats with YOUR C engine
  for path, status in pairs(files) do
    local full_path = state.path .. "/" .. path
    
    -- Call YOUR C diff function via FFI
    local diff_stats = compute_diff_with_c_engine(
      get_file_at_commit(commit1, path),
      get_file_at_commit(commit2, path)
    )
    
    -- Store in node.extra
    item.extra = {
      git_status = status,
      diff_stats = diff_stats,  -- YOUR custom data
      commit1 = commit1,
      commit2 = commit2,
    }
  end
end
```

### 3. Custom Filtering

```lua
function M.navigate(state, path, path_to_reveal, callback, async)
  local files = get_files_between_commits(commit1, commit2, state.path)
  
  -- FILTER as you want
  if state.filter_mode == "modified_only" then
    files = vim.tbl_filter(function(path, status)
      return status == "M"
    end, files)
  end
  
  if state.file_pattern then
    files = vim.tbl_filter(function(path, status)
      return path:match(state.file_pattern)
    end, files)
  end
  
  -- Build tree from filtered files
end
```

### 4. Custom Sorting

```lua
-- Sort by number of changes
file_items.advanced_sort(root.children, state, function(a, b)
  local a_stats = a.extra.diff_stats or {}
  local b_stats = b.extra.diff_stats or {}
  
  local a_changes = (a_stats.additions or 0) + (a_stats.deletions or 0)
  local b_changes = (b_stats.additions or 0) + (b_stats.deletions or 0)
  
  return a_changes > b_changes
end)
```

## Full Example: Custom Source

```lua
-- lua/neo-tree/sources/vscode_diff/init.lua
local M = {
  name = "vscode_diff",
  display_name = " 󰊢 VSCode Diff ",
}

local renderer = require("neo-tree.ui.renderer")
local file_items = require("neo-tree.sources.common.file-items")

-- Get files between ANY two commits
local function get_files_between_commits(commit1, commit2, cwd)
  local result = vim.system({
    "git", "diff", "--name-status", commit1, commit2
  }, { cwd = cwd, text = true }):wait()
  
  if result.code ~= 0 then
    return {}
  end
  
  local files = {}
  for _, line in ipairs(vim.split(result.stdout, "\n")) do
    if line ~= "" then
      local status, path = line:match("^(%S+)%s+(.+)$")
      if status and path then
        files[path] = status
      end
    end
  end
  return files
end

function M.navigate(state, path, path_to_reveal, callback, async)
  state.path = path or state.path or vim.fn.getcwd()
  
  -- Get custom parameters
  local commit1 = state.commit1 or "HEAD~1"
  local commit2 = state.commit2 or "HEAD"
  
  -- Get changed files
  local status_lookup = get_files_between_commits(commit1, commit2, state.path)
  
  -- Build tree
  local context = file_items.create_context()
  context.state = state
  
  local root = file_items.create_item(context, state.path, "directory")
  root.name = string.format("%s...%s", commit1, commit2)
  root.loaded = true
  context.folders[root.path] = root
  
  -- Add files
  for path, status in pairs(status_lookup) do
    local full_path = state.path .. "/" .. path
    local success, item = pcall(file_items.create_item, context, full_path, "file")
    if success then
      item.status = status
      item.extra = {
        git_status = status,
        commit1 = commit1,
        commit2 = commit2,
      }
    end
  end
  
  -- Expand and render
  state.default_expanded_nodes = {}
  for id, _ in pairs(context.folders) do
    table.insert(state.default_expanded_nodes, id)
  end
  
  renderer.show_nodes({ root }, state)
  
  if type(callback) == "function" then
    vim.schedule(callback)
  end
end

function M.setup(config, global_config)
  -- Add custom commands, events, etc.
end

return M
```

### Usage:

```vim
:Neotree vscode_diff commit1=HEAD~5 commit2=HEAD
:Neotree float vscode_diff commit1=main commit2=develop
```

## Verdict: Neo-tree IS Flexible Enough ✅

### Pros:
1. ✅ **Fully customizable** - Complete control over data and rendering
2. ✅ **Modern architecture** - Built on nui.nvim
3. ✅ **Well-designed API** - Clean source system
4. ✅ **Event system** - React to changes
5. ✅ **Component system** - Custom UI elements
6. ✅ **Active maintenance** - No breaking changes policy
7. ✅ **Can integrate** - With your C diff engine, git.lua module, etc.

### Cons:
1. ⚠️  Requires learning Neo-tree's component system (but well-documented)
2. ⚠️  More work than using built-in git_status (but WAY more powerful)
3. ⚠️  Need to understand file_items API (but examples exist)

### Comparison with Building from Scratch:

| Feature | Neo-tree Custom Source | From Scratch |
|---------|----------------------|--------------|
| Tree rendering | ✅ Built-in | ❌ Need to implement |
| File icons | ✅ Built-in | ❌ Need to implement |
| Keyboard navigation | ✅ Built-in | ❌ Need to implement |
| Floating windows | ✅ Built-in | ❌ Need to implement |
| Customization | ✅ Full control | ✅ Full control |
| Effort | 🟡 Medium | 🔴 High |
| Maintenance | ✅ Neo-tree handles UI | ❌ You handle everything |

## Recommendation

### For Your Use Case:

**Use a Custom Neo-tree Source** - It gives you:
1. All the UI/rendering infrastructure (don't reinvent the wheel)
2. Complete flexibility for git comparisons (any commit vs any commit)
3. Integration with your C diff engine
4. Custom components for diff stats
5. Beautiful, modern appearance
6. Active maintenance (Neo-tree team handles UI bugs)

### Implementation Path:

**Phase 1:** Basic custom source
- Compare two commits with git diff
- Basic tree rendering
- Open files in vscode-diff

**Phase 2:** Add custom components
- Show diff stats inline
- Add file size changes
- Color coding based on change amount

**Phase 3:** Advanced features
- Integration with C diff engine
- Custom filtering/sorting
- Keybindings for common workflows
- Preview diff stats in statusline

## Conclusion

Neo-tree is **absolutely flexible enough** for your needs. The custom source system is designed exactly for this kind of use case - you get all the UI infrastructure for free while having complete control over data retrieval and rendering.

You're not limited by Neo-tree's built-in git_status. You can create a source that does **anything** you want.
