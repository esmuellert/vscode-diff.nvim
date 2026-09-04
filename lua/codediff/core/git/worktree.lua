-- Git index and working-tree write operations.
local M = {}

local run_git_async = require("codediff.core.git.runner").run_async

-- Apply a unified diff patch to the git index (async)
-- Used for hunk-level staging: generates a patch for a single hunk and applies it
-- to the index without touching the working tree.
--
-- git_root: absolute path to git repository root
-- patch: string containing a valid unified diff patch
-- reverse: if true, reverse-apply the patch (used for unstaging)
-- callback: function(err) - nil err on success
-- Apply a unified diff patch via git apply (async)
-- Supports staging hunks (--cached), unstaging (--cached --reverse),
-- and discarding from working tree (--reverse, no --cached).
--
-- git_root: absolute path to git repository root
-- patch: string containing a valid unified diff patch
-- opts: table with optional flags:
--   cached: boolean - apply to index (default: true)
--   reverse: boolean - reverse-apply the patch (default: false)
-- callback: function(err) - nil err on success
function M.apply_patch(git_root, patch, opts, callback)
  -- Support old signature: apply_patch(git_root, patch, reverse, callback)
  if type(opts) == "boolean" then
    opts = { cached = true, reverse = opts }
  end
  opts = opts or {}
  if opts.cached == nil then
    opts.cached = true
  end

  local args = { "apply", "--unidiff-zero", "-" }
  if opts.cached then
    table.insert(args, 2, "--cached")
  end
  if opts.reverse then
    table.insert(args, 2, "--reverse")
  end

  if vim.system then
    if git_root and vim.fn.isdirectory(git_root) == 0 then
      callback("Directory does not exist: " .. git_root)
      return
    end

    vim.system(vim.list_extend({ "git" }, args), {
      cwd = git_root,
      stdin = patch,
      text = true,
    }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          callback(nil)
        else
          callback(result.stderr or "git apply failed")
        end
      end)
    end)
  else
    -- Fallback for older Neovim (< 0.10)
    local stderr_data = {}
    local stdin_pipe = vim.loop.new_pipe(false)
    local stderr_pipe = vim.loop.new_pipe(false)

    local handle
    ---@diagnostic disable-next-line: missing-fields
    handle = vim.loop.spawn("git", {
      args = args,
      cwd = git_root,
      stdio = { stdin_pipe, nil, stderr_pipe },
    }, function(code)
      if stdin_pipe then
        stdin_pipe:close()
      end
      if stderr_pipe then
        stderr_pipe:close()
      end
      if handle then
        handle:close()
      end

      vim.schedule(function()
        if code == 0 then
          callback(nil)
        else
          callback(table.concat(stderr_data) or "git apply failed")
        end
      end)
    end)

    if not handle then
      callback("Failed to spawn git process")
      return
    end

    if stderr_pipe then
      stderr_pipe:read_start(function(err, data)
        if data then
          table.insert(stderr_data, data)
        end
      end)
    end

    -- Write patch to stdin and close
    stdin_pipe:write(patch)
    stdin_pipe:shutdown()
  end
end

-- Stage a file (git add)
-- git_root: absolute path to git repository root
-- rel_path: relative path from git root
-- callback: function(err)
function M.stage_file(git_root, rel_path, callback)
  run_git_async({ "add", "--", rel_path }, { cwd = git_root }, function(err, _)
    if err then
      callback("Failed to stage file: " .. err)
    else
      callback(nil)
    end
  end)
end

-- Unstage a file (git reset HEAD)
-- git_root: absolute path to git repository root
-- rel_path: relative path from git root
-- callback: function(err)
function M.unstage_file(git_root, rel_path, callback)
  run_git_async({ "reset", "HEAD", "--", rel_path }, { cwd = git_root }, function(err, _)
    if err then
      callback("Failed to unstage file: " .. err)
    else
      callback(nil)
    end
  end)
end

-- Stage all files (git add -A)
-- git_root: absolute path to git repository root
-- callback: function(err)
function M.stage_all(git_root, callback)
  run_git_async({ "add", "-A" }, { cwd = git_root }, function(err, _)
    if err then
      callback("Failed to stage all files: " .. err)
    else
      callback(nil)
    end
  end)
end

-- Unstage all files (git reset HEAD)
-- git_root: absolute path to git repository root
-- callback: function(err)
function M.unstage_all(git_root, callback)
  run_git_async({ "reset", "HEAD" }, { cwd = git_root }, function(err, _)
    if err then
      callback("Failed to unstage all files: " .. err)
    else
      callback(nil)
    end
  end)
end

-- Restore/discard changes to a file (git checkout -- or git restore)
-- git_root: absolute path to git repository root
-- rel_path: relative path from git root
-- source: optional revision to restore from (e.g. commit hash, "origin/HEAD")
-- callback: function(err)
function M.restore_file(git_root, rel_path, source, callback)
  -- Support old 3-arg signature: restore_file(git_root, rel_path, callback)
  if type(source) == "function" then
    callback = source
    source = nil
  end

  -- git restore is preferred (Git 2.23+), fallback to checkout
  local restore_args = { "restore" }
  if source then
    table.insert(restore_args, "--source=" .. source)
  end
  table.insert(restore_args, "--")
  table.insert(restore_args, rel_path)

  run_git_async(restore_args, { cwd = git_root }, function(err, _)
    if err then
      -- Fallback to git checkout for older git versions
      local checkout_args = { "checkout" }
      if source then
        table.insert(checkout_args, source)
      end
      table.insert(checkout_args, "--")
      table.insert(checkout_args, rel_path)

      run_git_async(checkout_args, { cwd = git_root }, function(err2, _)
        if err2 then
          callback("Failed to restore file: " .. err2)
        else
          callback(nil)
        end
      end)
    else
      callback(nil)
    end
  end)
end

-- Delete untracked file or directory (git clean -fd)
-- git_root: absolute path to git repository root
-- rel_path: relative path from git root
-- callback: function(err)
function M.delete_untracked(git_root, rel_path, callback)
  run_git_async({ "clean", "-fd", "--", rel_path }, { cwd = git_root }, function(err, _)
    if err then
      callback("Failed to delete untracked file: " .. err)
    else
      callback(nil)
    end
  end)
end

return M
