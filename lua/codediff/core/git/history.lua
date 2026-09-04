-- Git commit history queries.
local M = {}

local run_git_async = require("codediff.core.git.runner").run_async

-- Get commit list for file history (async)
-- range: git range expression (e.g., "origin/main..HEAD", "HEAD~10..HEAD")
-- git_root: absolute path to git repository root
-- opts: optional table with keys:
--   path: file path to filter commits (relative to git_root)
--   limit: maximum number of commits to return
--   no_merges: exclude merge commits
--   reverse: reverse order (oldest first)
-- callback: function(err, commits) where commits is array of:
--   { hash, short_hash, author, date, date_relative, subject, ref_names, files_changed, insertions, deletions }
function M.get_commit_list(range, git_root, opts, callback)
  opts = opts or {}
  local is_single_file = opts.path and opts.path ~= ""
  local is_line_range = opts.line_range and is_single_file

  local args = {
    "log",
    "--pretty=format:%H%x00%h%x00%an%x00%at%x00%ar%x00%s%x00%D%x00",
  }

  if is_line_range then
    -- git log -L requires -p or -s format; --numstat/--shortstat/--follow are incompatible
    local l_arg = string.format("-L%d,%d:%s", opts.line_range[1], opts.line_range[2], opts.path)
    table.insert(args, l_arg)
  elseif is_single_file then
    -- For single file mode, use --numstat to get stats AND file path (for renames)
    table.insert(args, "--numstat")
    table.insert(args, "--follow")
  else
    -- For multi-file mode, use --shortstat for aggregate stats
    table.insert(args, "--shortstat")
  end

  if opts.no_merges then
    table.insert(args, "--no-merges")
  end

  if opts.limit then
    table.insert(args, "-n")
    table.insert(args, tostring(opts.limit))
  end

  if opts.reverse then
    table.insert(args, "--reverse")
  end

  if range and range ~= "" then
    table.insert(args, range)
  end

  -- For non-line-range single file, add -- path (line-range already includes the path in -L)
  if is_single_file and not is_line_range then
    table.insert(args, "--")
    table.insert(args, opts.path)
  end

  run_git_async(args, { cwd = git_root }, function(err, output)
    if err then
      callback(err, nil)
      return
    end

    local commits = {}
    local current_commit = nil

    for line in output:gmatch("[^\n]+") do
      -- Check if this is a commit line (contains null separators)
      if line:find("\0") then
        -- Save previous commit if exists
        if current_commit then
          table.insert(commits, current_commit)
        end

        local parts = vim.split(line, "\0")
        if #parts >= 7 then
          current_commit = {
            hash = parts[1],
            short_hash = parts[2],
            author = parts[3],
            date = tonumber(parts[4]),
            date_relative = parts[5],
            subject = parts[6],
            ref_names = parts[7] ~= "" and parts[7] or nil,
            files_changed = 0,
            insertions = 0,
            deletions = 0,
            file_path = is_line_range and opts.path or nil,
          }
        end
      elseif current_commit and not is_line_range and line:match("^%d+%s+%d+%s+") then
        -- Parse numstat line: "40\t12\tpath" or "0\t0\tlua/{old => new}/file.lua"
        local ins, del, path = line:match("^(%d+)%s+(%d+)%s+(.+)$")
        if ins and del and path then
          current_commit.insertions = (current_commit.insertions or 0) + tonumber(ins)
          current_commit.deletions = (current_commit.deletions or 0) + tonumber(del)
          current_commit.files_changed = (current_commit.files_changed or 0) + 1
          -- Extract actual file path, handling rename notation like "lua/{old => new}/file.lua"
          -- For renames, extract the old path (before =>)
          if path:match("{.*=>.*}") then
            -- Rename notation: extract old path
            -- Examples: "lua/{vscode-diff => codediff}/file.lua" or "lua/vscode-diff/{ => core}/git.lua"
            local prefix, old, _, suffix = path:match("^(.*)%{(.-)%s*=>%s*(.-)%}(.*)$")
            if prefix then
              -- Remove trailing slash from prefix if old is empty (move into subdir)
              if old == "" and prefix:sub(-1) == "/" then
                prefix = prefix:sub(1, -2)
              end
              current_commit.file_path = prefix .. old .. suffix
            else
              current_commit.file_path = path
            end
          else
            current_commit.file_path = path
          end
        end
      elseif current_commit and not is_line_range and line:match("%d+ file") then
        -- Parse shortstat line: " 3 files changed, 32 insertions(+), 8 deletions(-)"
        local files = line:match("(%d+) file")
        local ins = line:match("(%d+) insertion")
        local del = line:match("(%d+) deletion")
        current_commit.files_changed = tonumber(files) or 0
        current_commit.insertions = tonumber(ins) or 0
        current_commit.deletions = tonumber(del) or 0
      elseif current_commit and is_line_range then
        -- For line-range mode, count insertions/deletions from diff lines
        if line:match("^%+[^%+]") or (line == "+") then
          current_commit.insertions = current_commit.insertions + 1
          current_commit.files_changed = 1
        elseif line:match("^%-[^%-]") or (line == "-") then
          current_commit.deletions = current_commit.deletions + 1
          current_commit.files_changed = 1
        end
      end
    end

    -- Don't forget the last commit
    if current_commit then
      table.insert(commits, current_commit)
    end

    callback(nil, commits)
  end)
end

return M
