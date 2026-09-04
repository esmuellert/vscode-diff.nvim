-- Line statistics for Git file-change results.
local M = {}

local config = require("codediff.config")
local changes = require("codediff.core.git.changes")
local run_git_async = require("codediff.core.git.runner").run_async

local function parse_numstat(output)
  local stats = {}
  local records = vim.split(output or "", "\0", { plain = true })
  for index, record in ipairs(records) do
    local insertions, deletions, path = record:match("^([^\t]+)\t([^\t]+)\t(.*)$")
    if insertions then
      path = path ~= "" and path or records[index + 2]
      if path and path ~= "" then
        stats[path] = insertions == "-" and { insertions = 0, deletions = 0, binary = true }
          or { insertions = tonumber(insertions) or 0, deletions = tonumber(deletions) or 0, binary = false }
      end
    end
  end
  return stats
end

local function get_untracked_line_stats(path, max_bytes)
  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(path)
  if not stat or stat.type ~= "file" or stat.size > max_bytes then
    return nil
  end

  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local data = uv.fs_read(fd, stat.size, 0) or ""
  uv.fs_close(fd)
  if data:find("\0", 1, true) then
    return { insertions = 0, deletions = 0, binary = true }
  end

  local _, newlines = data:gsub("\n", "")
  local final_line = #data > 0 and data:sub(-1) ~= "\n" and 1 or 0
  return { insertions = newlines + final_line, deletions = 0, binary = false }
end

local function attach_line_stats(entries, stats)
  for _, entry in ipairs(entries or {}) do
    entry.line_stats = stats[entry.path]
  end
end

local function attach_untracked_line_stats(entries, git_root, max_bytes)
  for _, entry in ipairs(entries or {}) do
    if entry.status == "??" then
      entry.line_stats = get_untracked_line_stats(git_root .. "/" .. entry.path, max_bytes)
    end
  end
end

local function collect_line_stats(git_root, requests, callback)
  local remaining = #requests
  local first_error
  for _, request in ipairs(requests) do
    run_git_async(request.args, { cwd = git_root }, function(err, output)
      first_error = first_error or err
      if not err then
        local stats = parse_numstat(output)
        for _, entries in ipairs(request.entries) do
          attach_line_stats(entries, stats)
        end
      end
      remaining = remaining - 1
      if remaining == 0 then
        callback(first_error)
      end
    end)
  end
end

local function line_stats_options()
  return (config.options.explorer or {}).line_stats or {}
end

function M.get_status_with_line_stats(git_root, callback, pathspec)
  local options = line_stats_options()
  if not options.enabled then
    changes.get_status(git_root, callback, pathspec)
    return
  end

  changes.get_status(git_root, function(err, result)
    if err then
      callback(err, nil)
      return
    end
    collect_line_stats(git_root, {
      {
        args = vim.list_extend({ "diff", "--numstat", "-z", "-M", "--" }, pathspec or {}),
        entries = { result.unstaged, result.conflicts },
      },
      {
        args = vim.list_extend({ "diff", "--cached", "--numstat", "-z", "-M", "--" }, pathspec or {}),
        entries = { result.staged },
      },
    }, function(stats_err)
      if stats_err then
        callback(stats_err, nil)
        return
      end
      if options.count_untracked then
        attach_untracked_line_stats(result.unstaged, git_root, options.max_untracked_bytes or 1024 * 1024)
      end
      callback(nil, result)
    end)
  end, pathspec)
end

function M.get_diff_revision_with_line_stats(revision, git_root, callback, pathspec)
  local options = line_stats_options()
  if not options.enabled then
    changes.get_diff_revision(revision, git_root, callback, pathspec)
    return
  end

  changes.get_diff_revision(revision, git_root, function(err, result)
    if err then
      callback(err, nil)
      return
    end
    collect_line_stats(git_root, {
      {
        args = vim.list_extend({ "diff", "--numstat", "-z", "-M", revision, "--" }, pathspec or {}),
        entries = { result.unstaged },
      },
    }, function(stats_err)
      if stats_err then
        callback(stats_err, nil)
        return
      end
      if options.count_untracked then
        attach_untracked_line_stats(result.unstaged, git_root, options.max_untracked_bytes or 1024 * 1024)
      end
      callback(nil, result)
    end)
  end, pathspec)
end

function M.get_diff_revisions_with_line_stats(rev1, rev2, git_root, callback, pathspec)
  if not line_stats_options().enabled then
    changes.get_diff_revisions(rev1, rev2, git_root, callback, pathspec)
    return
  end

  changes.get_diff_revisions(rev1, rev2, git_root, function(err, result)
    if err then
      callback(err, nil)
      return
    end
    collect_line_stats(git_root, {
      {
        args = vim.list_extend({ "diff", "--numstat", "-z", "-M", rev1, rev2, "--" }, pathspec or {}),
        entries = { result.unstaged },
      },
    }, function(stats_err)
      if stats_err then
        callback(stats_err, nil)
        return
      end
      callback(nil, result)
    end)
  end, pathspec)
end

return M
