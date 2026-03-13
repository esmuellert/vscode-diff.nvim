local comments = require("codediff.ui.comments")
local session_mod = require("codediff.ui.lifecycle.session")
local config = require("codediff.config")

local function has_buffer_map(bufnr, mode, lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
    if map.lhs == lhs then
      return true
    end
  end
  return false
end

describe("CodeDiff Comments", function()
  local tabpage
  local bufnr
  local active_diffs
  local original_config

  before_each(function()
    tabpage = vim.api.nvim_get_current_tabpage()
    bufnr = vim.api.nvim_get_current_buf()
    active_diffs = session_mod.get_active_diffs()
    original_config = vim.deepcopy(config.options)
    config.options = vim.deepcopy(config.defaults)

    active_diffs[tabpage] = {
      mode = "explorer",
      original_revision = "abc123",
      modified_revision = "def456",
      original_path = "a.lua",
      modified_path = "a.lua",
      original_bufnr = bufnr,
      modified_bufnr = bufnr,
    }

    comments._reset_for_tests()
  end)

  after_each(function()
    comments._reset_for_tests()
    active_diffs[tabpage] = nil
    config.options = original_config
  end)

  it("submit clears extmarks and in-memory comments", function()
    local added = comments.add_comment("looks good")
    assert.is_true(added)

    local marks_before = vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace("codediff-comments"), 0, -1, {})
    assert.is_true(#marks_before > 0, "Expected pending comment extmarks before submit")

    local submitted = comments.submit_comments()
    assert.is_true(submitted)

    local marks_after = vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace("codediff-comments"), 0, -1, {})
    assert.equals(0, #marks_after, "Expected pending comment extmarks to be cleared after submit")
    assert.equals(0, #comments.get_comments(tabpage), "Expected in-memory comments to be cleared after submit")
  end)

  it("submit uses configured hook and still clears UI state", function()
    local hook_calls = 0
    local last_payload
    comments.set_submit_hook(function(payload, submitted_comments, context)
      hook_calls = hook_calls + 1
      last_payload = payload
      assert.equals(1, #submitted_comments)
      assert.equals("explorer", context.mode)
      return true
    end)

    assert.is_true(comments.add_comment("hook path"))
    assert.is_true(comments.submit_comments())

    assert.equals(1, hook_calls)
    assert.is_true(last_payload:find("hook path", 1, true) ~= nil)
    assert.equals(0, #comments.get_comments(tabpage))
  end)

  it("removes comment at cursor", function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    assert.is_true(comments.add_comment("typo here"))

    local marks_before = vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace("codediff-comments"), 0, -1, {})
    assert.equals(1, #marks_before)

    assert.is_true(comments.remove_comment())

    local marks_after = vim.api.nvim_buf_get_extmarks(bufnr, vim.api.nvim_create_namespace("codediff-comments"), 0, -1, {})
    assert.equals(0, #marks_after)
    assert.equals(0, #comments.get_comments(tabpage))
  end)

  it("removes comment by id", function()
    assert.is_true(comments.add_comment("first"))
    assert.is_true(comments.add_comment("second"))

    local pending = comments.get_comments(tabpage)
    assert.equals(2, #pending)

    local first_id = pending[1].id
    assert.is_true(comments.remove_comment(first_id))

    local after = comments.get_comments(tabpage)
    assert.equals(1, #after)
    assert.equals("second", after[1].text)
  end)

  it("edits comment by id", function()
    assert.is_true(comments.add_comment("original"))

    local pending = comments.get_comments(tabpage)
    local comment_id = pending[1].id

    assert.is_true(comments.edit_comment(comment_id, "updated"))

    local after = comments.get_comments(tabpage)
    assert.equals(1, #after)
    assert.equals("updated", after[1].text)
  end)

  it("opens edit editor at the end of existing comment text", function()
    assert.is_true(comments.add_comment("first line\nsecond line"))
    local pending = comments.get_comments(tabpage)
    assert.equals(1, #pending)

    assert.is_true(comments.open_edit_editor(pending[1].id))

    local editor_bufnr = vim.api.nvim_get_current_buf()
    local mode = vim.api.nvim_get_mode().mode
    assert.equals("i", mode:sub(1, 1))
    assert.is_true(has_buffer_map(editor_bufnr, "n", "<CR>"))
    assert.is_true(has_buffer_map(editor_bufnr, "n", "q"))

    local cursor = vim.api.nvim_win_get_cursor(0)
    assert.equals(2, cursor[1])
    assert.equals(#"second line", cursor[2])
  end)

  it("supports normal editor mode with normal-first editing", function()
    config.options.comments.ui.editor_mode = "normal"

    assert.is_true(comments.add_comment("alpha"))
    local pending = comments.get_comments(tabpage)
    assert.equals(1, #pending)

    assert.is_true(comments.open_edit_editor(pending[1].id))

    local editor_bufnr = vim.api.nvim_get_current_buf()
    local mode = vim.api.nvim_get_mode().mode
    assert.equals("n", mode:sub(1, 1))
    assert.is_true(has_buffer_map(editor_bufnr, "n", "<CR>"))
    assert.is_true(has_buffer_map(editor_bufnr, "n", "q"))
    assert.is_false(has_buffer_map(editor_bufnr, "i", "<CR>"))
    assert.is_false(has_buffer_map(editor_bufnr, "i", "q"))
  end)

  it("lists pending comments in quickfix", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    assert.is_true(comments.add_comment("first pending note"))

    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    assert.is_true(comments.add_comment("third pending note"))

    assert.is_true(comments.list_comments())

    local qf = vim.fn.getqflist({ title = 1, items = 1 })
    assert.equals("CodeDiff pending comments (2)", qf.title)
    assert.equals(2, #qf.items)
    assert.equals(bufnr, qf.items[1].bufnr)
    assert.equals(1, qf.items[1].lnum)
    assert.equals("I", qf.items[1].type)
    assert.is_true(qf.items[1].text:find("c1 [left] a.lua:1 first pending note", 1, true) ~= nil)
    assert.equals(bufnr, qf.items[2].bufnr)
    assert.equals(3, qf.items[2].lnum)
    assert.equals("I", qf.items[2].type)
    assert.is_true(qf.items[2].text:find("c2 [left] a.lua:3 third pending note", 1, true) ~= nil)

    pcall(vim.cmd, "cclose")
  end)

  it("submit payload includes structured comment identifiers", function()
    local payload = nil
    comments.set_submit_hook(function(formatted)
      payload = formatted
      return true
    end)

    assert.is_true(comments.add_comment("payload shape"))
    assert.is_true(comments.submit_comments())

    assert.is_true(payload:find("CodeDiff review (1 comment)", 1, true) ~= nil)
    assert.is_true(payload:find("a.lua:1 (old)", 1, true) ~= nil)
    assert.is_true(payload:find("payload shape", 1, true) ~= nil)
  end)

  it("submit syncs line numbers from extmarks", function()
    local submitted_comments = nil
    comments.set_submit_hook(function(_, pending)
      submitted_comments = pending
      return true
    end)

    assert.is_true(comments.add_comment("line shift"))
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new first line" })

    assert.is_true(comments.submit_comments())
    assert.equals(1, #submitted_comments)
    assert.equals(2, submitted_comments[1].line)
  end)

  it("submit keeps comments hidden for other files in the same session", function()
    local submitted_comments = nil
    comments.set_submit_hook(function(_, pending)
      submitted_comments = pending
      return true
    end)

    assert.is_true(comments.add_comment("from file A"))

    -- Simulate explorer/history switching to another file in the same pane.
    -- Hidden comments lose extmarks temporarily but must still be submitted.
    active_diffs[tabpage].original_path = "b.lua"

    assert.is_true(comments.submit_comments())
    assert.equals(1, #submitted_comments)
    assert.equals("from file A", submitted_comments[1].text)
  end)

  it("does not clear comments when hook returns false", function()
    comments.set_submit_hook(function()
      return false
    end)

    assert.is_true(comments.add_comment("keep me"))
    assert.is_false(comments.submit_comments())
    assert.equals(1, #comments.get_comments(tabpage))
  end)

  it("adds ranged comment with explicit line1/line2", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3", "line4", "line5" })
    assert.is_true(comments.add_comment("range note", 2, 4))

    local pending = comments.get_comments(tabpage)
    assert.equals(1, #pending)
    assert.equals(2, pending[1].line)
    assert.equals(4, pending[1].end_line)
    assert.equals("range note", pending[1].text)
  end)

  it("single-line range does not set end_line", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2" })
    assert.is_true(comments.add_comment("single", 3, 3))

    local pending = comments.get_comments(tabpage)
    assert.equals(1, #pending)
    assert.is_nil(pending[1].end_line)
  end)

  it("ranged comment appears in quickfix with range text", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })
    assert.is_true(comments.add_comment("range qf", 2, 5))

    assert.is_true(comments.list_comments())

    local qf = vim.fn.getqflist({ title = 1, items = 1 })
    assert.equals(1, #qf.items)
    assert.equals(2, qf.items[1].lnum)
    assert.is_true(qf.items[1].text:find("a.lua:2-5", 1, true) ~= nil)

    pcall(vim.cmd, "cclose")
  end)

  it("submit payload shows range format for ranged comments", function()
    local payload = nil
    comments.set_submit_hook(function(formatted)
      payload = formatted
      return true
    end)

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d" })
    assert.is_true(comments.add_comment("range payload", 1, 3))
    assert.is_true(comments.submit_comments())

    assert.is_true(payload:find("a.lua:1-3 (old)", 1, true) ~= nil)
    assert.is_true(payload:find("range payload", 1, true) ~= nil)
  end)

  it("submit syncs ranged comment end_line from extmarks", function()
    local submitted_comments = nil
    comments.set_submit_hook(function(_, pending)
      submitted_comments = pending
      return true
    end)

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d" })
    assert.is_true(comments.add_comment("shift range", 2, 4))

    -- Insert a line before the range, shifting both start and end
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new first" })

    assert.is_true(comments.submit_comments())
    assert.equals(1, #submitted_comments)
    assert.equals(3, submitted_comments[1].line)
    assert.equals(5, submitted_comments[1].end_line)
  end)
end)
