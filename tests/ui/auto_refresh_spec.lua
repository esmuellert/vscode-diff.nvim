describe("mutable revision synchronization", function()
  local original_auto_refresh
  local original_git
  local original_lifecycle
  local auto_refresh
  local original_trigger
  local current_session
  local callbacks
  local trigger_count
  local original_bufnr
  local modified_bufnr
  local tabpage

  before_each(function()
    original_auto_refresh = package.loaded["codediff.ui.auto_refresh"]
    original_git = package.loaded["codediff.core.git"]
    original_lifecycle = package.loaded["codediff.ui.lifecycle"]

    original_bufnr = vim.api.nvim_create_buf(false, true)
    modified_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(original_bufnr, 0, -1, false, { "old original" })
    vim.api.nvim_buf_set_lines(modified_bufnr, 0, -1, false, { "old modified" })
    tabpage = vim.api.nvim_get_current_tabpage()
    current_session = {
      git_root = "/repo",
      original_bufnr = original_bufnr,
      modified_bufnr = modified_bufnr,
      original_revision = ":2",
      modified_revision = ":3",
      original = { relative = "file.txt" },
      modified = { relative = "file.txt" },
    }
    callbacks = {}
    trigger_count = 0

    package.loaded["codediff.ui.lifecycle"] = {
      get_session = function(candidate)
        assert.equals(tabpage, candidate)
        return current_session
      end,
    }
    package.loaded["codediff.core.git"] = {
      get_file_content = function(revision, git_root, path, callback)
        assert.equals("/repo", git_root)
        assert.equals("file.txt", path)
        callbacks[revision] = callback
      end,
    }
    package.loaded["codediff.ui.auto_refresh"] = nil
    auto_refresh = require("codediff.ui.auto_refresh")
    original_trigger = auto_refresh.trigger
    auto_refresh.trigger = function()
      trigger_count = trigger_count + 1
    end
  end)

  after_each(function()
    auto_refresh.trigger = original_trigger
    package.loaded["codediff.ui.auto_refresh"] = original_auto_refresh
    package.loaded["codediff.core.git"] = original_git
    package.loaded["codediff.ui.lifecycle"] = original_lifecycle
    if vim.api.nvim_buf_is_valid(original_bufnr) then
      vim.api.nvim_buf_delete(original_bufnr, { force = true })
    end
    if vim.api.nvim_buf_is_valid(modified_bufnr) then
      vim.api.nvim_buf_delete(modified_bufnr, { force = true })
    end
  end)

  it("completes only after every mutable target settles", function()
    local completed = 0
    auto_refresh.sync_mutable_buffers(tabpage, function()
      completed = completed + 1
    end)

    assert.is_function(callbacks[":2"])
    assert.is_function(callbacks[":3"])
    assert.equals(0, completed)

    callbacks[":2"](nil, { "new original" })
    assert.is_true(vim.wait(1000, function()
      return vim.api.nvim_buf_get_lines(original_bufnr, 0, -1, false)[1] == "new original"
    end, 10))
    assert.equals(0, completed)

    callbacks[":3"](nil, { "new modified" })
    assert.is_true(vim.wait(1000, function()
      return completed == 1
    end, 10))
    assert.equals("new modified", vim.api.nvim_buf_get_lines(modified_bufnr, 0, -1, false)[1])
    assert.equals(2, trigger_count)
  end)

  it("completes immediately when the session no longer exists", function()
    current_session = nil
    local completed = 0

    auto_refresh.sync_mutable_buffers(tabpage, function()
      completed = completed + 1
    end)

    assert.equals(1, completed)
    assert.same({}, callbacks)
  end)

  it("completes immediately when neither side is mutable", function()
    current_session.original_revision = "HEAD"
    current_session.modified_revision = nil
    local completed = 0

    auto_refresh.sync_mutable_buffers(tabpage, function()
      completed = completed + 1
    end)

    assert.equals(1, completed)
    assert.same({}, callbacks)
  end)

  it("counts errors as settled", function()
    current_session.modified_revision = nil
    local completed = 0
    auto_refresh.sync_mutable_buffers(tabpage, function()
      completed = completed + 1
    end)

    callbacks[":2"]("git failed")

    assert.is_true(vim.wait(1000, function()
      return completed == 1
    end, 10))
    assert.equals("old original", vim.api.nvim_buf_get_lines(original_bufnr, 0, -1, false)[1])
  end)

  it("does not write after the owning session is replaced", function()
    current_session.modified_revision = nil
    local completed = 0
    auto_refresh.sync_mutable_buffers(tabpage, function()
      completed = completed + 1
    end)
    current_session = {}

    callbacks[":2"](nil, { "stale" })

    assert.is_true(vim.wait(1000, function()
      return completed == 1
    end, 10))
    assert.equals("old original", vim.api.nvim_buf_get_lines(original_bufnr, 0, -1, false)[1])
    assert.equals(0, trigger_count)
  end)
end)
