local snapshot_cache = require("codediff.comments.snapshot_cache")

describe("CodeDiff Snapshot Cache", function()
  local tmpdir

  before_each(function()
    snapshot_cache._reset_for_tests()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    snapshot_cache._set_dir_for_tests(tmpdir)
  end)

  after_each(function()
    snapshot_cache._reset_for_tests()
    vim.fn.delete(tmpdir, "rf")
  end)

  local function make_comments()
    return {
      { id = 1, side = "left", path = "a.lua", line = 10, text = "looks good" },
      { id = 2, side = "right", path = "b.lua", line = 20, end_line = 25, text = "needs work" },
    }
  end

  describe("session_id", function()
    it("produces stable deterministic hashes", function()
      local id1 = snapshot_cache.session_id("/repo", "abc123", "def456")
      local id2 = snapshot_cache.session_id("/repo", "abc123", "def456")
      assert.equals(id1, id2)
      assert.is_string(id1)
      assert.is_true(#id1 > 0)
    end)

    it("produces different hashes for different inputs", function()
      local id1 = snapshot_cache.session_id("/repo", "abc123", "def456")
      local id2 = snapshot_cache.session_id("/repo", "abc123", "fff999")
      local id3 = snapshot_cache.session_id("/other", "abc123", "def456")
      assert.is_not.equals(id1, id2)
      assert.is_not.equals(id1, id3)
    end)
  end)

  describe("save + restore", function()
    it("round-trips comments in memory", function()
      local sid = snapshot_cache.session_id("/repo", "a", "b")
      local comments = make_comments()
      snapshot_cache.save(sid, comments)

      local restored = snapshot_cache.restore(sid)
      assert.is_not_nil(restored)
      assert.equals(2, #restored)
      assert.equals("looks good", restored[1].text)
      assert.equals("right", restored[2].side)
      assert.equals(25, restored[2].end_line)
    end)

    it("returns nil for unknown session_id", function()
      assert.is_nil(snapshot_cache.restore("nonexistent"))
    end)

    it("round-trips comments from disk after memory reset", function()
      local sid = snapshot_cache.session_id("/repo", "a", "b")
      local comments = make_comments()
      snapshot_cache.save(sid, comments)

      snapshot_cache._reset_for_tests()

      local restored = snapshot_cache.restore(sid)
      assert.is_not_nil(restored)
      assert.equals(2, #restored)
      assert.equals("looks good", restored[1].text)
      assert.equals(20, restored[2].line)
    end)

    it("saves and restores an empty comments list", function()
      local sid = snapshot_cache.session_id("/repo", "a", "b")
      snapshot_cache.save(sid, {})

      local restored = snapshot_cache.restore(sid)
      -- Accept either empty table or nil
      if restored ~= nil then
        assert.equals(0, #restored)
      end
    end)
  end)

  describe("remove", function()
    it("causes subsequent restore to return nil", function()
      local sid = snapshot_cache.session_id("/repo", "a", "b")
      snapshot_cache.save(sid, make_comments())

      snapshot_cache.remove(sid)

      assert.is_nil(snapshot_cache.restore(sid))
    end)

    it("deletes the disk file", function()
      local sid = snapshot_cache.session_id("/repo", "a", "b")
      snapshot_cache.save(sid, make_comments())

      -- Verify a file was written
      local files_before = vim.fn.glob(tmpdir .. "/*", false, true)
      assert.is_true(#files_before > 0, "Expected disk file after save")

      snapshot_cache.remove(sid)

      local files_after = vim.fn.glob(tmpdir .. "/*", false, true)
      assert.equals(0, #files_after, "Expected disk file to be removed")
    end)
  end)
end)
