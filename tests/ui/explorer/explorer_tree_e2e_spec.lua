-- E2E: explorer tree content and file navigation
-- Converted from tests/e2e/explorer_tree.lua.

local h = dofile("tests/helpers.lua")
h.ensure_plugin_loaded()

describe("Explorer tree (E2E)", function()
  local repo

  before_each(function()
    require("codediff").setup({})
    repo = h.create_temp_git_repo()
    repo.write_file("src/a.txt", { "aaa" })
    repo.write_file("src/b.txt", { "bbb" })
    repo.write_file("c.txt", { "ccc" })
    repo.git("add .")
    repo.git("commit -m initial")
    repo.write_file("src/a.txt", { "aaa modified" })
    repo.write_file("src/b.txt", { "bbb modified" })
    repo.write_file("c.txt", { "ccc modified" })
    vim.cmd("edit " .. repo.path("c.txt"))
  end)

  after_each(function()
    h.close_extra_tabs()
    if repo then
      repo.cleanup()
    end
  end)

  it("renders the changed files and reacts to ]f navigation", function()
    vim.cmd("CodeDiff")
    assert.is_true(h.wait_for_explorer(5000))
    assert.is_true(h.wait_for_diff_ready(5000))

    local _, explorer_buf = h.find_window_by_filetype("codediff-explorer")
    local lines = h.get_buffer_lines(explorer_buf)
    assert.is_true(#lines > 0, "explorer buffer should have content")

    local content = h.get_buffer_content(explorer_buf)
    -- At least one of the changed files must be listed.
    local has_a = content:find("a.txt", 1, true) ~= nil
    local has_b = content:find("b.txt", 1, true) ~= nil
    local has_c = content:find("c.txt", 1, true) ~= nil
    assert.is_true(has_a or has_b or has_c,
      "explorer should list at least one changed file (a/b/c.txt), got:\n" .. content)

    -- The unstaged group header must be present.
    h.assert_contains(content, "Changes",
      "explorer should show the 'Changes' group header for unstaged files")

    -- ]f navigates to the next file — after firing it the modified pane must
    -- still hold visible content (empty implies a broken navigation path).
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("]f", true, false, true), "nx", false)
    vim.wait(500)

    local lifecycle = require("codediff.ui.lifecycle")
    local _, mod_buf = lifecycle.get_buffers(vim.api.nvim_get_current_tabpage())
    assert.is_not_nil(mod_buf, "modified buffer should still exist after ]f")
    local mod_content = h.get_buffer_content(mod_buf)
    assert.is_true(mod_content ~= nil and #mod_content > 0,
      "modified pane should have content after ]f navigation")
  end)
end)
