# File Sidebar for Git Changes - Recommendation

## Executive Summary

**Recommendation: Use Neo-tree.nvim's built-in `git_status` source**

Neo-tree.nvim already provides exactly what you need - a beautiful, modern file sidebar that shows git changes. It's the best-practice solution in the Neovim ecosystem with ~5,000 stars, active maintenance, and a no-breaking-changes policy.

## Why Neo-tree.nvim?

### 1. Already Has What You Need ✅

Neo-tree comes with a built-in `git_status` source that:
- Shows all modified, added, deleted, untracked files
- Displays git status icons (M, A, D, ??, etc.)
- Tree structure for organized directory view
- Built-in commands: git add, unstage, revert, commit, push
- Multiple view modes: sidebar, floating window, netrw-style

### 2. Modern Architecture ✅

- Built on **nui.nvim** (the best Neovim UI library)
- Component-based rendering system
- Public API and event system
- Extensible source architecture
- Async file watching with libuv

### 3. Beautiful Appearance ✅

- Git status colors and icons
- File icons via nvim-web-devicons
- Indent guides
- Smooth animations
- Customizable components
- Multiple layout options

### 4. Performance ✅

- Async operations (non-blocking)
- Efficient rendering
- Smart refresh on git events
- File system watching

## Comparison with Alternatives

### nvim-tree.lua
- **Stars**: ~8,000
- **Status**: Feature-frozen (no new major features)
- **Verdict**: ❌ Not recommended - less extensible, no new features

### Custom Implementation
- **Control**: Full control
- **Effort**: High - reinventing the wheel
- **Verdict**: ❌ Not recommended - use Neo-tree instead

## Implementation Guide

### Quick Start

#### 1. Install Neo-tree

```lua
-- Using lazy.nvim
{
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons", -- optional but recommended
  }
}
```

#### 2. Basic Usage

```vim
:Neotree git_status           " Open in sidebar
:Neotree float git_status     " Open in floating window
:Neotree git_status git_base=main  " Compare with branch
```

### Integration with vscode-diff.nvim

#### Option 1: Simple Command Integration

Add this to your `plugin/vscode-diff.lua`:

```lua
-- Command to show git status list
vim.api.nvim_create_user_command("VscodeDiffList", function()
  vim.cmd("Neotree float git_status")
end, { desc = "Show git changed files" })
```

Users can then:
1. Run `:VscodeDiffList` to see changed files
2. Navigate to desired file in Neo-tree
3. Press Enter to edit the file
4. Run `:VscodeDiff HEAD` to view the diff

#### Option 2: Custom Keybinding Integration

Configure Neo-tree to open files directly in vscode-diff:

```lua
-- In user's Neo-tree config
require("neo-tree").setup({
  git_status = {
    window = {
      mappings = {
        -- Press 'dd' on a file to open it in vscode-diff
        ["dd"] = function(state)
          local node = state.tree:get_node()
          if node and node.type == "file" then
            -- Close neo-tree
            vim.cmd("Neotree close")
            -- Open the file
            vim.cmd("edit " .. node.path)
            -- Open diff with HEAD
            vim.cmd("VscodeDiff HEAD")
          end
        end,
        
        -- Or press 'd1' for HEAD~1
        ["d1"] = function(state)
          local node = state.tree:get_node()
          if node and node.type == "file" then
            vim.cmd("Neotree close")
            vim.cmd("edit " .. node.path)
            vim.cmd("VscodeDiff HEAD~1")
          end
        end,
      }
    }
  }
})
```

### Advanced: Custom Neo-tree Source (Future Enhancement)

If you later need tighter integration, you can create a custom Neo-tree source:

```
vscode-diff.nvim/
└── lua/
    └── neo-tree/
        └── sources/
            └── vscode_diff/
                ├── init.lua          # Main source
                ├── lib/
                │   └── items.lua     # Get file list with your git module
                └── components.lua    # Custom rendering
```

This allows:
- Custom filtering of files
- Show diff stats inline
- Custom UI components
- Tight integration with your C diff engine

## Recommended Approach

**Phase 1: Start Simple**
1. Document that users should install Neo-tree
2. Add `:VscodeDiffList` command that opens Neo-tree git_status
3. Document the workflow in your README

**Phase 2: Enhance (Optional)**
1. Add example Neo-tree configuration to your docs
2. Show how to create custom keybindings
3. Add convenience functions for common workflows

**Phase 3: Advanced (Only if needed)**
1. Create custom Neo-tree source
2. Show diff stats in the file list
3. Custom filtering and rendering

## Benefits of This Approach

1. **Minimal Work**: Neo-tree already exists and works
2. **Best Practices**: Using the ecosystem's best solution
3. **User Choice**: Users can use any file tree plugin they prefer
4. **Maintainability**: Less code to maintain in your plugin
5. **Modern**: Beautiful, performant, actively maintained
6. **Extensible**: Easy to customize or extend later

## Documentation Example for README

Add to your vscode-diff.nvim README:

```markdown
## Git Changed Files List

To see a list of all git changed files with a beautiful sidebar, we recommend
using [Neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim)'s 
built-in `git_status` source.

### Quick Start

1. Install Neo-tree.nvim (see their installation docs)

2. Use the built-in command:
   ```vim
   :Neotree git_status
   ```

3. Navigate to a file and press Enter to edit it, then run:
   ```vim
   :VscodeDiff HEAD
   ```

### Convenience Command

Add this to your config for quick access:
```lua
vim.api.nvim_create_user_command("VscodeDiffList", function()
  vim.cmd("Neotree float git_status")
end, {})
```

Now you can run `:VscodeDiffList` to quickly see all changed files!
```

## Conclusion

**Use Neo-tree.nvim's `git_status` source** - it's the modern, performant, 
beautiful solution that follows Neovim best practices. Don't reinvent the 
wheel; leverage the excellent tools the community has already built.

Neo-tree is:
- ✅ Already feature-complete for your needs
- ✅ Actively maintained (~5,000 stars)
- ✅ Modern architecture (nui.nvim based)
- ✅ Beautiful appearance
- ✅ Easy to integrate with vscode-diff
- ✅ Extensible if needed later
