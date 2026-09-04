-- Review a pull request without checking out its branch.
local M = {}

local pull_request = require("codediff.core.pull_request")
local parse = require("codediff.commands.parse")
local explorer = require("codediff.commands.handlers.explorer")

--- Fetch a pull request and open its merge-base diff.
--- @param number number
--- @param opts table { remote?: string, base?: string }
--- @param global_opts table
--- @param pathspec string[]|nil
function M.run(number, opts, global_opts, pathspec)
  vim.notify(string.format("Fetching pull request #%d from %s...", number, opts.remote or "origin"), vim.log.levels.INFO)
  parse.resolve_working_root(global_opts, function(git_root)
    pull_request.fetch(number, git_root, opts, function(err, revisions)
      if parse.failed(err) then
        return
      end
      vim.schedule(function()
        local review_opts = vim.tbl_extend("force", global_opts, { repo = git_root })
        explorer.run_merge_base(revisions.base_revision, revisions.head_revision, review_opts, pathspec)
      end)
    end)
  end)
end

--- Delete cached refs for one pull request.
--- @param number number
--- @param opts table { remote?: string }
--- @param global_opts table
function M.clean(number, opts, global_opts)
  parse.resolve_working_root(global_opts, function(git_root)
    pull_request.clean(number, git_root, opts, function(err, deleted)
      if parse.failed(err) then
        return
      end
      vim.schedule(function()
        vim.notify(
          deleted == 0 and string.format("No cached refs for pull request #%d", number) or string.format("Removed %d cached ref(s) for pull request #%d", deleted, number),
          vim.log.levels.INFO
        )
      end)
    end)
  end)
end

--- Delete all cached pull request refs, optionally for one remote.
--- @param opts table { remote?: string }
--- @param global_opts table
function M.clean_all(opts, global_opts)
  parse.resolve_working_root(global_opts, function(git_root)
    pull_request.clean_all(git_root, opts, function(err, deleted)
      if parse.failed(err) then
        return
      end
      vim.schedule(function()
        local scope = opts.remote and string.format(" for remote '%s'", opts.remote) or ""
        vim.notify(deleted == 0 and "No cached pull request refs" .. scope or string.format("Removed %d cached pull request ref(s)%s", deleted, scope), vim.log.levels.INFO)
      end)
    end)
  end)
end

return M
