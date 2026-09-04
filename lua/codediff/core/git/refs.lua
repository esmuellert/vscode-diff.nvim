-- Remote and local Git ref operations.
local M = {}

local run_git_async = require("codediff.core.git.runner").run_async

--- List selected refs on a remote and resolve its default branch.
--- @param remote string
--- @param refs string[]
--- @param git_root string
--- @param callback fun(err: string|nil, result: table|nil)
function M.list_remote_refs(remote, refs, git_root, callback)
  local args = { "ls-remote", "--symref", remote, "HEAD" }
  vim.list_extend(args, refs)
  run_git_async(args, { cwd = git_root }, function(err, output)
    if err then
      callback(err, nil)
      return
    end

    local result = { refs = {} }
    for line in output:gmatch("[^\r\n]+") do
      local symbolic = line:match("^ref:%s+(refs/heads/[^%s]+)%s+HEAD$")
      if symbolic then
        result.default_branch = symbolic
      else
        local hash, ref = line:match("^(%x+)%s+([^%s]+)$")
        if hash and ref then
          result.refs[ref] = hash
        end
      end
    end
    callback(nil, result)
  end)
end

--- Force-fetch remote refs into explicit local refs.
--- @param remote string
--- @param refspecs table[] { source: string, destination: string }
--- @param git_root string
--- @param callback fun(err: string|nil)
function M.fetch_remote_refs(remote, refspecs, git_root, callback)
  local args = { "fetch", "--no-tags", remote }
  for _, refspec in ipairs(refspecs) do
    args[#args + 1] = "+" .. refspec.source .. ":" .. refspec.destination
  end
  run_git_async(args, { cwd = git_root }, function(err)
    callback(err and vim.trim(err) or nil)
  end)
end

--- List local refs below a namespace prefix.
--- @param prefix string
--- @param git_root string
--- @param callback fun(err: string|nil, refs: table[]|nil)
function M.list_local_refs(prefix, git_root, callback)
  run_git_async({ "for-each-ref", "--format=%(refname)%09%(objectname)", prefix }, { cwd = git_root }, function(err, output)
    if err then
      callback(err, nil)
      return
    end

    local refs = {}
    for line in output:gmatch("[^\r\n]+") do
      local name, object = line:match("^([^\t]+)\t(%x+)$")
      if name and object then
        refs[#refs + 1] = { name = name, object = object }
      end
    end
    callback(nil, refs)
  end)
end

--- Delete local refs, verifying that none changed since they were listed.
--- @param refs table[] { name: string, object: string }
--- @param git_root string
--- @param callback fun(err: string|nil, deleted: number)
function M.delete_local_refs(refs, git_root, callback)
  local index = 1
  local deleted = 0

  local function delete_next()
    local ref = refs[index]
    if not ref then
      callback(nil, deleted)
      return
    end

    run_git_async({ "update-ref", "-d", ref.name, ref.object }, { cwd = git_root }, function(err)
      if err then
        callback(string.format("Failed to delete ref '%s': %s", ref.name, vim.trim(err)), deleted)
        return
      end
      deleted = deleted + 1
      index = index + 1
      delete_next()
    end)
  end

  delete_next()
end

return M
