-- Git repository discovery and path handling.
local M = {}

local run_git_async = require("codediff.core.git.runner").run_async

-- Get git root directory for the given file (async)
-- callback: function(err, git_root)
function M.get_git_root(file_path, callback)
  -- Handle both file paths and directory paths
  local dir
  if vim.fn.isdirectory(file_path) == 1 then
    dir = file_path
  else
    dir = vim.fn.fnamemodify(file_path, ":h")
  end

  -- Normalize path separators for consistency
  dir = dir:gsub("\\", "/")

  run_git_async({ "rev-parse", "--show-toplevel" }, { cwd = dir }, function(err, output)
    if err then
      callback("Not in a git repository", nil)
    else
      local git_root = vim.trim(output)
      -- Resolve full path to handle short paths/symlinks and normalize
      git_root = vim.fn.fnamemodify(git_root, ":p")
      -- Ensure git_root uses forward slashes for consistency
      git_root = git_root:gsub("\\", "/")
      -- Remove trailing slash if present (fnamemodify :p adds it on some systems)
      if git_root:sub(-1) == "/" then
        git_root = git_root:sub(1, -2)
      end
      callback(nil, git_root)
    end
  end)
end

-- Get git directory path (handles worktrees correctly)
-- git_root: absolute path to git repository root
-- callback: function(err, git_dir)
function M.get_git_dir(git_root, callback)
  run_git_async({ "rev-parse", "--git-dir" }, { cwd = git_root }, function(err, output)
    if err then
      callback("Failed to get git directory: " .. err, nil)
    else
      local git_dir = vim.trim(output)
      -- Make absolute path if relative
      if not git_dir:match("^/") and not git_dir:match("^%a:") then
        git_dir = git_root .. "/" .. git_dir
      end
      callback(nil, git_dir)
    end
  end)
end

-- Get relative path of file within git repository (sync, pure computation)
function M.get_relative_path(file_path, git_root)
  local abs_path = vim.fn.fnamemodify(file_path, ":p")
  abs_path = abs_path:gsub("\\", "/")
  git_root = git_root:gsub("\\", "/")
  local rel_path = abs_path:sub(#git_root + 2)
  return rel_path
end

-- Get git root directory synchronously (for completion)
-- Returns git_root or nil if not in a git repo
function M.get_git_root_sync(file_path)
  local dir
  if vim.fn.isdirectory(file_path) == 1 then
    dir = file_path
  else
    dir = vim.fn.fnamemodify(file_path, ":h")
  end

  local cmd = { "git", "-C", dir, "rev-parse", "--show-toplevel" }
  local result = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end

  local git_root = vim.trim(result[1])
  git_root = git_root:gsub("\\", "/")
  return git_root
end

return M
