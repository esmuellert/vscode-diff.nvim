-- Regression test for https://github.com/esmuellert/codediff.nvim/issues/496
-- `diff.compact = true` must also apply when the first file is selected from
-- the explorer, not just when a diff is opened directly.
--
-- Pre-fix: the explorer's placeholder session had `stored_diff_result = {}`.
-- `setup_all_keymaps` called `compact.refresh` immediately after session
-- creation, and the guard `not compact_default_applied and stored_diff_result`
-- evaluated the truthy `{}` and burned the one-shot latch. When the user then
-- selected a file, the second `compact.refresh` call skipped `M.enable` because
-- the latch was already set.

local h = require("tests.helpers")

describe("Issue #496 regression — diff.compact default applies on explorer select", function()
  local repo
  local lifecycle = require("codediff.ui.lifecycle")

  before_each(function()
    h.ensure_plugin_loaded()
    require("codediff").setup({ diff = { compact = true, compact_context_lines = 3 } })
    lifecycle.cleanup_all()
    repo = h.create_temp_git_repo()

    -- File big enough to have foldable unchanged regions when compact is on.
    repo.write_file("file.txt", {
      "l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8", "l9", "l10",
      "l11", "l12", "l13", "l14", "l15", "l16", "l17", "l18", "l19", "l20",
    })
    repo.git("add .")
    repo.git("commit -m c")
    -- Single-line change in the middle → 2 folded regions above and below.
    repo.write_file("file.txt", {
      "l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8", "l9", "l10",
      "CHANGED",
      "l12", "l13", "l14", "l15", "l16", "l17", "l18", "l19", "l20",
    })
  end)

  after_each(function()
    h.close_extra_tabs()
    lifecycle.cleanup_all()
    if repo then repo.cleanup() end
    -- Reset compact so subsequent tests don't inherit our test's true value.
    require("codediff").setup({ diff = { compact = false } })
  end)

  it("compact_mode is enabled after selecting a file from :CodeDiff explorer", function()
    vim.cmd("edit " .. repo.path("file.txt"))
    require("codediff.commands").vscode_diff({ fargs = {} })

    -- Wait for the explorer to open with a current selection.
    local explorer
    assert.is_true(vim.wait(8000, function()
      for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local sess = lifecycle.get_session(tp)
        if sess and sess.explorer and sess.explorer.current_file_path ~= nil then
          explorer = sess.explorer
          return true
        end
      end
      return false
    end, 50), "explorer did not open with a current file selection")

    -- Wait for the real diff to land (stored_diff_result.changes populated),
    -- then for compact.refresh to see it and enable compact mode.
    local tabpage = explorer.tabpage
    local compact_on = vim.wait(8000, function()
      local sess = lifecycle.get_session(tabpage)
      return sess and sess.compact_mode == true
    end, 50)

    local sess = lifecycle.get_session(tabpage)
    assert.is_not_nil(sess)
    -- Pre-fix: compact_mode was nil (latch got burned on the placeholder).
    assert.is_true(compact_on,
      "diff.compact=true default did not apply to explorer-selected file; "
        .. "compact_mode=" .. tostring(sess.compact_mode)
        .. " compact_default_applied=" .. tostring(sess.compact_default_applied)
        .. " has_changes=" .. tostring(sess.stored_diff_result and sess.stored_diff_result.changes ~= nil))
  end)

  it("compact_default_applied stays false until a real diff is loaded", function()
    -- Guard against a future regression that flips the latch on any truthy
    -- `stored_diff_result` again — the placeholder must not burn the one-shot.
    vim.cmd("edit " .. repo.path("file.txt"))
    require("codediff.commands").vscode_diff({ fargs = {} })

    -- Between session creation and the first file selection, the placeholder
    -- session exists but has no real diff yet. Snapshot the latch immediately
    -- after session creation — it should still be nil/false at that point.
    local placeholder_seen = vim.wait(4000, function()
      for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local sess = lifecycle.get_session(tp)
        if sess and sess.stored_diff_result then
          -- Snapshot: at this instant, has the latch been burned inappropriately?
          if sess.stored_diff_result.changes == nil then
            -- Placeholder frame: compact_default_applied MUST still be nil/false.
            assert.is_falsy(sess.compact_default_applied,
              "compact_default_applied was set on the placeholder session (regression of #496)")
            return true
          end
        end
      end
      return false
    end, 50)
    assert.is_true(placeholder_seen, "never observed a placeholder session frame to inspect")
  end)
end)
