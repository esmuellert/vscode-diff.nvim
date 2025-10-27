# Git Integration Implementation

## Summary

Implemented git revision support for the vscode-diff.nvim plugin, allowing users to compare their current buffer with any git revision.

## What Was Implemented

### 1. New Git Module (`lua/vscode-diff/git.lua`)

A comprehensive git operations module with async support:

**Functions:**
- `get_git_root(file_path)` - Get git repository root directory
- `get_relative_path(file_path, git_root)` - Get file path relative to repo root
- `is_in_git_repo(file_path)` - Check if file is in a git repository
- `get_file_at_revision(revision, file_path, callback)` - Async file content retrieval
- `validate_revision(revision, file_path, callback)` - Validate git revision exists

**Key Features:**
- **Async by default**: Uses `vim.system()` (Neovim 0.10+) or `vim.loop.spawn()` (fallback)
- **Non-blocking**: All git operations that fetch content are async
- **Error handling**: Provides user-friendly error messages
- **Compatibility**: Works on Neovim 0.7+ with different async implementations

### 2. Enhanced VscodeDiff Command

The `:VscodeDiff` command now supports two modes:

**Mode 1: Git Diff (Single Argument)**
```vim
:VscodeDiff <revision>
```
- Compares current buffer with specified git revision
- Left buffer: Git version (readonly)
- Right buffer: Current content (readonly)
- Opens in new tab
- Examples: `HEAD`, `HEAD~1`, `main`, `v1.0.0`, commit hashes

**Mode 2: File Diff (Two Arguments)**
```vim
:VscodeDiff <file_a> <file_b>
```
- Original behavior: compare two files

### 3. Documentation

Created comprehensive documentation in `docs/git-integration.md`:
- Usage examples
- Error handling guide
- Lua API reference
- Implementation details
- Future enhancement ideas

Updated `README.md` with:
- Git integration in features list
- Git as a prerequisite
- Usage examples for both modes
- Lua API examples

## Best Practices Followed

Based on analysis of popular plugins (gitsigns.nvim, diffview.nvim):

1. **Async Operations**
   - Used `vim.system()` for modern Neovim
   - Fallback to `vim.loop.spawn()` for older versions
   - Non-blocking file retrieval from git

2. **Git Commands**
   - `git show <revision>:<path>` for file content
   - `git rev-parse --show-toplevel` for repo root
   - `git rev-parse --verify` for revision validation

3. **Error Handling**
   - Check if file is in git repo
   - Validate file exists in revision
   - User-friendly error messages
   - Graceful degradation

4. **User Experience**
   - Loading notifications
   - Clear error messages
   - Readonly buffers to prevent accidental edits
   - Opens in new tab automatically

## Technical Details

### Async Implementation

The plugin supports two async approaches:

**Modern (Neovim 0.10+):**
```lua
vim.system({ "git", "show", object }, {
  cwd = git_root,
  text = true,
}, callback)
```

**Legacy (Neovim 0.7-0.9):**
```lua
vim.loop.spawn("git", {
  args = { "show", object },
  cwd = git_root,
  stdio = { nil, stdout, stderr },
}, callback)
```

### Command Flow

1. User runs `:VscodeDiff HEAD~1`
2. Plugin checks if current buffer is a file
3. Plugin checks if file is in a git repository
4. Plugin validates the git revision exists
5. Async: Fetch file content from git
6. On success: Compute diff and render in new tab
7. On error: Show user-friendly error message

### Git Object Format

Files are retrieved using:
```
<revision>:<relative-path>
```

Examples:
- `HEAD:lua/vscode-diff/git.lua`
- `main:README.md`
- `abc123:src/file.js`

## Testing

Verified with manual git repository test:
- Created test repo with multiple commits
- Tested `git show HEAD:file`
- Tested `git show HEAD~1:file`
- Confirmed commands work correctly
- Verified error handling for non-existent files

## Future Enhancements

Potential improvements identified:

1. **Rename Detection**
   - Use `git log --follow` to track renames
   - Show diff even when file was renamed

2. **Two Revision Comparison**
   - Support `:VscodeDiff <rev1> <rev2>` syntax
   - Compare any two revisions

3. **Staging Area**
   - Compare working directory vs staged
   - Support index comparison

4. **Merge Conflicts**
   - Show three-way merge view
   - Help resolve conflicts

5. **Performance**
   - Cache git root lookups
   - Cache file content for commonly used revisions

## Files Modified/Created

**Created:**
- `lua/vscode-diff/git.lua` - New git operations module
- `docs/git-integration.md` - Comprehensive git integration docs

**Modified:**
- `plugin/vscode-diff.lua` - Enhanced command to support git mode
- `README.md` - Updated features and usage sections

## Compatibility

- **Minimum**: Neovim 0.7.0 (with vim.loop fallback)
- **Recommended**: Neovim 0.10+ (for vim.system)
- **External**: Requires git command-line tool

## Usage Examples

```vim
" Compare with last commit
:VscodeDiff HEAD

" Compare with 3 commits ago
:VscodeDiff HEAD~3

" Compare with a branch
:VscodeDiff main

" Compare with a tag
:VscodeDiff v1.0.0

" Traditional file diff still works
:VscodeDiff old.lua new.lua
```

## Conclusion

The git integration follows best practices from established Neovim git plugins, provides a smooth async experience, and maintains backward compatibility while adding powerful new functionality.
