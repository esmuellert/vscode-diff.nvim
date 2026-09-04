-- Pull request ref discovery and fetching across Git hosting providers.
local M = {}

local git = require("codediff.core.git")

local local_ref_root = "refs/codediff/pull-requests"

local ref_patterns = {
  {
    merge = "refs/pull/%d/merge", -- GitHub and Azure DevOps
    head = "refs/pull/%d/head",
  },
  {
    merge = "refs/merge-requests/%d/merge", -- GitLab
    head = "refs/merge-requests/%d/head",
  },
}

local function remote_key(remote)
  return remote:gsub("[^%w._-]", "_")
end

local function local_remote_prefix(remote)
  return string.format("%s/%s/", local_ref_root, remote_key(remote))
end

local function local_ref(remote, number, kind)
  return string.format("%s%d/%s", local_remote_prefix(remote), number, kind)
end

local function base_ref(base)
  if not base then
    return nil
  end
  return base:match("^refs/heads/") and base or "refs/heads/" .. base
end

local function fetch_refs(ctx, refspecs, callback)
  git.fetch_remote_refs(ctx.remote, refspecs, ctx.git_root, function(err)
    if err then
      callback(string.format("Failed to fetch pull request from remote '%s': %s", ctx.remote, err))
      return
    end
    callback(nil)
  end)
end

local function resolve_base(ctx, callback)
  local source = base_ref(ctx.base) or ctx.remote_info.default_branch
  if not source then
    callback("Could not determine the pull request target branch; pass --base <branch>")
    return
  end

  local destination = local_ref(ctx.remote, ctx.number, "base")
  fetch_refs(ctx, { { source = source, destination = destination } }, function(err)
    if err then
      callback(err)
      return
    end
    git.resolve_revision(destination, ctx.git_root, callback)
  end)
end

local function finish_with_head(ctx, head_revision, callback)
  resolve_base(ctx, function(err, base_revision)
    if err then
      callback(err, nil)
      return
    end
    callback(nil, {
      base_revision = base_revision,
      head_revision = head_revision,
      remote = ctx.remote,
    })
  end)
end

local function fetch_merge(ctx, source, callback)
  local destination = local_ref(ctx.remote, ctx.number, "merge")
  fetch_refs(ctx, { { source = source, destination = destination } }, function(err)
    if err then
      callback(err, nil)
      return
    end
    git.get_revision_parents(destination, ctx.git_root, function(parent_err, parents)
      if parent_err then
        callback("Failed to inspect the pull request merge commit: " .. parent_err, nil)
        return
      end
      if #parents < 2 then
        callback("Pull request merge ref is not a two-parent merge commit", nil)
        return
      end
      if ctx.base then
        finish_with_head(ctx, parents[2], callback)
      else
        callback(nil, {
          base_revision = parents[1],
          head_revision = parents[2],
          remote = ctx.remote,
        })
      end
    end)
  end)
end

local function fetch_head(ctx, source, callback)
  local destination = local_ref(ctx.remote, ctx.number, "head")
  fetch_refs(ctx, { { source = source, destination = destination } }, function(err)
    if err then
      callback(err, nil)
      return
    end
    git.resolve_revision(destination, ctx.git_root, function(head_err, head_revision)
      if head_err then
        callback(head_err, nil)
        return
      end
      finish_with_head(ctx, head_revision, callback)
    end)
  end)
end

local function first_available(refs, candidates)
  for _, candidate in ipairs(candidates) do
    if refs[candidate] then
      return candidate
    end
  end
end

local function clean_prefix(prefix, git_root, callback)
  git.list_local_refs(prefix, git_root, function(list_err, refs)
    if list_err then
      callback("Failed to list cached pull request refs: " .. vim.trim(list_err), nil)
      return
    end
    git.delete_local_refs(refs, git_root, callback)
  end)
end

--- Delete every cached ref for one pull request on a remote.
--- @param number number
--- @param git_root string Repository root
--- @param opts table? { remote?: string }
--- @param callback fun(err: string|nil, deleted: number|nil)
function M.clean(number, git_root, opts, callback)
  if type(number) ~= "number" or number < 1 or number % 1 ~= 0 then
    callback("Pull request number must be a positive integer", nil)
    return
  end
  opts = opts or {}
  local prefix = string.format("%s%d/", local_remote_prefix(opts.remote or "origin"), number)
  clean_prefix(prefix, git_root, callback)
end

--- Delete cached pull request refs, optionally scoped to one remote.
--- @param git_root string Repository root
--- @param opts table? { remote?: string }
--- @param callback fun(err: string|nil, deleted: number|nil)
function M.clean_all(git_root, opts, callback)
  opts = opts or {}
  local prefix = opts.remote and local_remote_prefix(opts.remote) or local_ref_root .. "/"
  clean_prefix(prefix, git_root, callback)
end

--- Fetch a pull request without checking it out and return its review range.
--- @param number number Pull request or merge request number
--- @param git_root string Repository root
--- @param opts table? { remote?: string, base?: string }
--- @param callback fun(err: string|nil, result: table|nil)
function M.fetch(number, git_root, opts, callback)
  opts = opts or {}
  local ctx = {
    number = number,
    git_root = git_root,
    remote = opts.remote or "origin",
    base = opts.base,
  }
  local requested_refs = {}
  local merge_refs = {}
  local head_refs = {}

  for _, pattern in ipairs(ref_patterns) do
    local merge_ref = pattern.merge:format(number)
    local head_ref = pattern.head:format(number)
    merge_refs[#merge_refs + 1] = merge_ref
    head_refs[#head_refs + 1] = head_ref
    requested_refs[#requested_refs + 1] = merge_ref
    requested_refs[#requested_refs + 1] = head_ref
  end
  local requested_base = base_ref(opts.base)
  if requested_base then
    requested_refs[#requested_refs + 1] = requested_base
  end

  git.list_remote_refs(ctx.remote, requested_refs, git_root, function(err, remote_info)
    if err then
      callback(string.format("Failed to query remote '%s': %s", ctx.remote, vim.trim(err)), nil)
      return
    end
    ctx.remote_info = remote_info

    local merge_ref = first_available(remote_info.refs, merge_refs)
    if merge_ref then
      fetch_merge(ctx, merge_ref, callback)
      return
    end

    local head_ref = first_available(remote_info.refs, head_refs)
    if head_ref then
      fetch_head(ctx, head_ref, callback)
      return
    end

    callback(string.format("Pull request #%d was not found on remote '%s'", number, ctx.remote), nil)
  end)
end

return M
