-- Regression: async work for an older selection must not overwrite a newer
-- staged/unstaged selection of the same path. A path-only stale check cannot
-- distinguish those two explorer entries.

local h = dofile("tests/helpers.lua")
h.ensure_plugin_loaded()

local lifecycle = require("codediff.ui.lifecycle")

local function setup_command()
  local commands = require("codediff.commands")
  vim.api.nvim_create_user_command("CodeDiff", function(opts)
    commands.vscode_diff(opts)
  end, { nargs = "*", bang = true })
end

describe("explorer stale same-path selections", function()
  local repo
  local original_cwd
  local git
  local view
  local real_resolve_revision
  local real_update

  before_each(function()
    require("codediff").setup({ explorer = { auto_refresh = false } })
    setup_command()
    original_cwd = vim.fn.getcwd()
    repo = h.create_temp_git_repo()

    repo.write_file("race.lua", { "local value = 1", "return value" })
    repo.git("add race.lua")
    repo.git("commit -m initial")
    repo.write_file("race.lua", { "local value = 2", "return value" })
    repo.git("add race.lua")
    repo.write_file("race.lua", { "local value = 2", "return value + 1" })

    git = require("codediff.core.git")
    view = require("codediff.ui.view")
    real_resolve_revision = git.resolve_revision
    real_update = view.update
  end)

  after_each(function()
    git.resolve_revision = real_resolve_revision
    view.update = real_update
    pcall(function()
      vim.cmd("tabnew")
      vim.cmd("tabonly")
    end)
    vim.fn.chdir(original_cwd)
    if repo then
      repo.cleanup()
    end
  end)

  it("ignores an older callback when the same path changes group", function()
    vim.fn.chdir(repo.dir)
    vim.cmd("edit " .. repo.path("race.lua"))
    vim.cmd("CodeDiff")

    local explorer
    assert.is_true(
      vim.wait(10000, function()
        for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
          local session = lifecycle.get_session(tabpage)
          if
            session
            and session.explorer
            and session.explorer.current_file_path == "race.lua"
            and session.original_revision == ":0"
            and session.modified_revision == nil
            and session.stored_diff_result
            and session.stored_diff_result.changes
          then
            explorer = session.explorer
            return true
          end
        end
        return false
      end, 20),
      "CodeDiff explorer did not become ready"
    )

    local callbacks = {}
    git.resolve_revision = function(_, _, callback)
      callbacks[#callbacks + 1] = callback
    end

    local updates = {}
    view.update = function(_, session_config)
      updates[#updates + 1] = session_config
      return true
    end

    local common = { path = "race.lua", status = "M", git_root = explorer.git_root }
    explorer.on_file_select(vim.tbl_extend("force", common, { group = "unstaged" }), { force = true })
    explorer.on_file_select(vim.tbl_extend("force", common, { group = "staged" }), { force = true })
    assert.equal(2, #callbacks)

    local head = vim.trim(repo.git("rev-parse HEAD"))
    callbacks[2](nil, head) -- Newer staged selection completes first.
    callbacks[1](nil, head) -- Older unstaged selection completes last.

    assert.is_true(
      vim.wait(1000, function()
        return #updates > 0
      end, 10),
      "the current selection did not update the view"
    )
    assert.equal(1, #updates, "stale same-path callback also updated the view")
    assert.equal(":0", updates[1].modified_revision, "the staged selection should be the only update")
  end)
end)
