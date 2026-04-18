local git = require("codediff.core.git")
local helpers = require("tests.helpers")

describe("History merge commit support", function()
  local repo = nil

  before_each(function()
    repo = helpers.create_temp_git_repo()

    repo.write_file("target.txt", { "base" })
    repo.git("add target.txt")
    repo.git("commit -m 'base commit'")

    repo.git("checkout -b feature")
    repo.write_file("target.txt", { "feature change" })
    repo.git("add target.txt")
    repo.git("commit -m 'feature change'")

    repo.git("checkout main")
    repo.write_file("main.txt", { "main branch change" })
    repo.git("add main.txt")
    repo.git("commit -m 'main change'")

    repo.git("merge --no-ff feature -m 'merge feature'")
  end)

  after_each(function()
    if repo then
      repo.cleanup()
      repo = nil
    end
  end)

  it("includes merge commits in single-file history", function()
    local done = false
    local err_result = nil
    local commits_result = nil

    git.get_commit_list("", repo.dir, { path = "target.txt" }, function(err, commits)
      err_result = err
      commits_result = commits
      done = true
    end)

    helpers.wait_async(5000, function()
      return done
    end)

    assert.is_nil(err_result)
    assert.is_table(commits_result)
    assert.is_true(#commits_result >= 2)

    local merge_commit = nil
    for _, commit in ipairs(commits_result) do
      if commit.subject == "merge feature" then
        merge_commit = commit
        break
      end
    end

    assert.is_not_nil(merge_commit, "Expected file history to include merge commit")
    assert.equal(2, merge_commit.parent_count)
    assert.is_not_nil(merge_commit.parent_revision)
    assert.equal("target.txt", merge_commit.file_path)
  end)

  it("lists merge commit files against first parent", function()
    local head_output = repo.git("rev-parse HEAD")
    local merge_hash = vim.trim(head_output)

    local list_done = false
    local commits_result = nil
    git.get_commit_list("", repo.dir, { path = "target.txt" }, function(_, commits)
      commits_result = commits
      list_done = true
    end)

    helpers.wait_async(5000, function()
      return list_done
    end)

    local merge_commit = nil
    for _, commit in ipairs(commits_result or {}) do
      if commit.hash == merge_hash then
        merge_commit = commit
        break
      end
    end

    assert.is_not_nil(merge_commit, "Expected HEAD merge commit in history list")

    local done = false
    local err_result = nil
    local files_result = nil
    git.get_commit_files(merge_commit.hash, repo.dir, { parent_revision = merge_commit.parent_revision }, function(err, files)
      err_result = err
      files_result = files
      done = true
    end)

    helpers.wait_async(5000, function()
      return done
    end)

    assert.is_nil(err_result)
    assert.is_table(files_result)
    assert.is_true(#files_result >= 1)
    assert.equal("target.txt", files_result[1].path)
    assert.equal("M", files_result[1].status)
  end)
end)
