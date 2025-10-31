-- Git operations module for vscode-diff
local M = {}

-- Run a git command asynchronously
-- Uses vim.system if available (Neovim 0.10+), falls back to vim.loop.spawn
local function run_git_async(args, opts, callback)
  opts = opts or {}

  -- Use vim.system if available (Neovim 0.10+)
  if vim.system then
    vim.system(
      vim.list_extend({ "git" }, args),
      {
        cwd = opts.cwd,
        text = true,
      },
      function(result)
        if result.code == 0 then
          callback(nil, result.stdout or "")
        else
          callback(result.stderr or "Git command failed", nil)
        end
      end
    )
  else
    -- Fallback to vim.loop.spawn for older Neovim versions
    local stdout_data = {}
    local stderr_data = {}

    local handle
    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)

    ---@diagnostic disable-next-line: missing-fields
    handle = vim.loop.spawn("git", {
      args = args,
      cwd = opts.cwd,
      stdio = { nil, stdout, stderr },
    }, function(code)
      if stdout then stdout:close() end
      if stderr then stderr:close() end
      if handle then handle:close() end

      vim.schedule(function()
        if code == 0 then
          callback(nil, table.concat(stdout_data))
        else
          callback(table.concat(stderr_data) or "Git command failed", nil)
        end
      end)
    end)

    if not handle then
      callback("Failed to spawn git process", nil)
      return
    end

    if stdout then
      stdout:read_start(function(err, data)
        if err then
          callback(err, nil)
        elseif data then
          table.insert(stdout_data, data)
        end
      end)
    end

    if stderr then
      stderr:read_start(function(err, data)
        if err then
          callback(err, nil)
        elseif data then
          table.insert(stderr_data, data)
        end
      end)
    end
  end
end

-- Get git root directory for the given file
function M.get_git_root(file_path)
  local dir = vim.fn.fnamemodify(file_path, ":h")

  -- Run synchronously for simplicity in this case
  local result = vim.system and
    vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = dir, text = true }):wait()
    or nil

  if vim.system then
    if result and result.code == 0 then
      return vim.trim(result.stdout)
    end
  else
    -- Fallback for older Neovim
    local output = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
    if vim.v.shell_error == 0 and #output > 0 then
      return output[1]
    end
  end

  return nil
end

-- Get relative path of file within git repository
function M.get_relative_path(file_path, git_root)
  local abs_path = vim.fn.fnamemodify(file_path, ":p")
  local rel_path = abs_path:sub(#git_root + 2) -- +2 for the trailing slash
  return rel_path
end

-- Check if a file is in a git repository
function M.is_in_git_repo(file_path)
  return M.get_git_root(file_path) ~= nil
end

-- Get file content from a specific git revision
-- revision: e.g., "HEAD", "HEAD~1", commit hash, branch name, tag
-- file_path: absolute path to the file
-- callback: function(err, lines) where lines is a table of strings
function M.get_file_at_revision(revision, file_path, callback)
  local git_root = M.get_git_root(file_path)

  if not git_root then
    callback("Not in a git repository", nil)
    return
  end

  local rel_path = M.get_relative_path(file_path, git_root)
  local git_object = revision .. ":" .. rel_path

  run_git_async(
    { "show", git_object },
    { cwd = git_root },
    function(err, output)
      if err then
        -- Try to provide better error messages
        if err:match("does not exist") or err:match("exists on disk, but not in") then
          callback(string.format("File '%s' not found in revision '%s'", rel_path, revision), nil)
        else
          callback(err, nil)
        end
        return
      end

      -- Split output into lines
      local lines = vim.split(output, "\n")

      -- Remove last empty line if present
      if lines[#lines] == "" then
        table.remove(lines, #lines)
      end

      callback(nil, lines)
    end
  )
end

-- Validate a git revision exists
function M.validate_revision(revision, file_path, callback)
  local git_root = M.get_git_root(file_path)

  if not git_root then
    callback("Not in a git repository")
    return
  end

  run_git_async(
    { "rev-parse", "--verify", revision },
    { cwd = git_root },
    function(err)
      if err then
        callback(string.format("Invalid revision '%s': %s", revision, err))
      else
        callback(nil)
      end
    end
  )
end

return M
