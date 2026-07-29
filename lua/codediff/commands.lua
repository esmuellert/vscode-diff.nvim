-- Command implementations for vscode-diff
local M = {}

-- Subcommands available for :CodeDiff
M.SUBCOMMANDS = { "merge", "file", "dir", "history", "install" }

local git = require("codediff.core.git")
local lifecycle = require("codediff.ui.lifecycle")
local config = require("codediff.config")
local view = require("codediff.ui.view")
local path = require("codediff.core.path")
local ap = require("codediff.core.argparse")

--- Parse triple-dot syntax for merge-base comparisons.
-- @param arg string: The argument to parse
-- @return string|nil, string|nil: base_rev, target_rev (nil if not triple-dot syntax)
local function parse_triple_dot(arg)
  if not arg then
    return nil, nil
  end
  local base, target = arg:match("^(.+)%.%.%.(.*)$")
  if base then
    return base, target ~= "" and target or nil
  end
  return nil, nil
end

-- Resolve the git root for "working repo" modes (explorer, history) and call
-- on_ok(git_root, is_override). Resolution order: the --repo/-C override, else
-- the current buffer's file, else cwd. This is the single place the --repo/-C
-- override is applied for these modes.
local function resolve_working_root(global_opts, on_ok)
  local override = global_opts and global_opts.repo
  if override then
    git.get_git_root(override, function(err, git_root)
      if err then
        vim.schedule(function()
          vim.notify("Not a git repository: " .. override, vim.log.levels.ERROR)
        end)
        return
      end
      on_ok(git_root, true)
    end)
    return
  end

  local current_file = vim.api.nvim_buf_get_name(0)
  local cwd = vim.fn.getcwd()
  if current_file ~= "" then
    git.get_git_root(current_file, function(err_file, git_root_file)
      if not err_file then
        on_ok(git_root_file, false)
        return
      end
      -- Buffer path failed, fall back to cwd
      git.get_git_root(cwd, function(err_cwd, git_root_cwd)
        if not err_cwd then
          on_ok(git_root_cwd, false)
          return
        end
        vim.schedule(function()
          vim.notify("Not in a git repository", vim.log.levels.ERROR)
        end)
      end)
    end)
  else
    git.get_git_root(cwd, function(err_cwd, git_root)
      if err_cwd then
        vim.schedule(function()
          vim.notify(err_cwd, vim.log.levels.ERROR)
        end)
        return
      end
      on_ok(git_root, false)
    end)
  end
end

--- Handles diffing the current buffer against a given git revision.
-- @param revision string: The git revision (e.g., "HEAD", commit hash, branch name) to compare the current file against.
-- @param revision2 string?: Optional second revision. If provided, compares revision vs revision2.
-- @param global_opts table?: Global options (e.g., { layout = "inline" })
-- This function chains async git operations to get git root, resolve revision to hash, and get file content.
local function handle_git_diff(revision, revision2, global_opts)
  local current_buf = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buf)
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = current_buf })

  -- Diffing the current buffer against a revision requires a real on-disk file.
  -- Reject scratch/quickfix/terminal/dashboard buffers (buftype ~= "") and
  -- codediff:// virtual diff buffers (re-diffing one is not meaningful).
  if current_file == "" or buftype ~= "" then
    vim.notify("Current buffer is not a file", vim.log.levels.ERROR)
    return
  end
  if current_file:match("^codediff://") then
    vim.notify("Cannot diff a codediff:// virtual buffer", vim.log.levels.ERROR)
    return
  end

  -- Determine filetype from current buffer (sync operation, no git involved)
  local filetype = vim.bo[0].filetype
  if not filetype or filetype == "" then
    filetype = vim.filetype.match({ filename = current_file }) or ""
  end

  -- Async chain: get_git_root -> resolve_revision -> get_file_content -> render_diff
  git.get_git_root(current_file, function(err_root, git_root)
    if err_root then
      vim.schedule(function()
        vim.notify(err_root, vim.log.levels.ERROR)
      end)
      return
    end

    local relative_path = git.get_relative_path(current_file, git_root)

    git.resolve_revision(revision, git_root, function(err_resolve, commit_hash)
      if err_resolve then
        vim.schedule(function()
          vim.notify(err_resolve, vim.log.levels.ERROR)
        end)
        return
      end

      -- Resolve the file's path at the original revision (handles renames/copies)
      git.resolve_path_at_revision(commit_hash, git_root, relative_path, function(_, original_path)
        if revision2 then
          -- Compare two revisions
          git.resolve_revision(revision2, git_root, function(err_resolve2, commit_hash2)
            if err_resolve2 then
              vim.schedule(function()
                vim.notify(err_resolve2, vim.log.levels.ERROR)
              end)
              return
            end

            -- Resolve path at modified revision too
            git.resolve_path_at_revision(commit_hash2, git_root, relative_path, function(_, modified_path)
              vim.schedule(function()
                ---@type SessionConfig
                local session_config = {
                  mode = "standalone",
                  git_root = git_root,
                  original = path.make_ref(original_path, git_root),
                  modified = path.make_ref(modified_path, git_root),
                  original_revision = commit_hash,
                  modified_revision = commit_hash2,
                  layout = global_opts.layout,
                  exit_on_close = global_opts.exit_on_close,
                }
                view.create(session_config, filetype)
              end)
            end)
          end)
        else
          -- Compare revision vs working tree
          vim.schedule(function()
            ---@type SessionConfig
            local session_config = {
              mode = "standalone",
              git_root = git_root,
              original = path.make_ref(original_path, git_root),
              modified = path.make_ref(relative_path, git_root),
              original_revision = commit_hash,
              modified_revision = "WORKING",
              layout = global_opts.layout,
              exit_on_close = global_opts.exit_on_close,
            }
            view.create(session_config, filetype)
          end)
        end
      end)
    end)
  end)
end

local function handle_file_diff(file_a, file_b, global_opts)
  -- Determine filetype from first file
  local filetype = vim.filetype.match({ filename = file_a }) or ""

  -- Snapshot state before creating diff tab (for argv cleanup below)
  local prev_tab = vim.api.nvim_get_current_tabpage()
  local prev_tab_bufs = vim.api.nvim_tabpage_list_wins(prev_tab)
  local is_single_win_tab = #prev_tab_bufs == 1

  -- Create diff view (no pre-reading needed, :edit will load content)
  ---@type SessionConfig
  local session_config = {
    mode = "standalone",
    git_root = nil,
    original = path.make_ref(file_a, nil),
    modified = path.make_ref(file_b, nil),
    original_revision = nil,
    modified_revision = nil,
    layout = global_opts.layout,
    exit_on_close = global_opts.exit_on_close,
  }
  view.create(session_config, filetype)

  -- Clean up leftover tab from command-line args (git difftool scenario).
  -- When invoked as `nvim "$LOCAL" "$REMOTE" +"CodeDiff file ..."`, neovim
  -- creates a tab with the first argv file. Now that the diff tab exists,
  -- that original tab is redundant. Close it remotely (without switching to
  -- it) and defer to avoid interfering with startup autocmds / persistence.
  -- Guard: only trigger when argv files match the diff files (so running
  -- `:CodeDiff file a b` from an existing session won't close unrelated tabs).
  local argc = vim.fn.argc()
  if argc == 2 and is_single_win_tab then
    local argv0 = vim.fn.fnamemodify(vim.fn.argv(0), ":p")
    local argv1 = vim.fn.fnamemodify(vim.fn.argv(1), ":p")
    local abs_a = vim.fn.fnamemodify(file_a, ":p")
    local abs_b = vim.fn.fnamemodify(file_b, ":p")
    local argv_matches = (argv0 == abs_a and argv1 == abs_b) or (argv0 == abs_b and argv1 == abs_a)
    if argv_matches then
      vim.schedule(function()
        if vim.api.nvim_tabpage_is_valid(prev_tab) and prev_tab ~= vim.api.nvim_get_current_tabpage() then
          local tab_nr = vim.api.nvim_tabpage_get_number(prev_tab)
          vim.cmd(tab_nr .. "tabclose")
        end
        pcall(vim.cmd, "%argdelete")
      end)
    end
  end
end

local function handle_dir_diff(dir1, dir2, global_opts)
  local dir_mod = require("codediff.core.dir")

  -- Expand ~ and environment variables in paths
  dir1 = vim.fn.expand(dir1)
  dir2 = vim.fn.expand(dir2)

  if vim.fn.isdirectory(dir1) == 0 then
    vim.notify("Not a directory: " .. dir1, vim.log.levels.ERROR)
    return
  end
  if vim.fn.isdirectory(dir2) == 0 then
    vim.notify("Not a directory: " .. dir2, vim.log.levels.ERROR)
    return
  end

  local diff = dir_mod.diff_directories(dir1, dir2)
  local status_result = diff.status_result

  if #status_result.unstaged == 0 and #status_result.staged == 0 then
    vim.notify("No differences between directories", vim.log.levels.INFO)
    return
  end

  ---@type SessionConfig
  local session_config = {
    mode = "explorer",
    git_root = nil, -- nil signals non-git (directory) mode
    original = path.make_ref(diff.root1, nil),
    modified = path.make_ref(diff.root2, nil),
    original_revision = nil,
    modified_revision = nil,
    layout = global_opts.layout,
    exit_on_close = global_opts.exit_on_close,
    explorer_data = {
      status_result = status_result,
    },
  }

  view.create(session_config, "")
end

-- Handle file history command
-- range: git range (e.g., "origin/main..HEAD", "HEAD~10")
-- file_path: optional file path to filter history
-- line_range: optional {start, end} for line-range history (git log -L)
local function handle_history(range, file_path, flags, line_range, global_opts)
  flags = flags or {} -- Default to empty table for backward compat

  -- Expand file_path before async context (vim.fn.expand can't be called in fast event)
  local expanded_file_path = nil
  if file_path then
    expanded_file_path = vim.fn.expand(file_path)
    if vim.fn.filereadable(expanded_file_path) ~= 1 then
      expanded_file_path = file_path
    end
  end

  local function open_history(git_root)
    -- Build options for commit list
    local history_opts = {
      no_merges = true,
    }

    -- Apply reverse flag if present
    if flags.reverse then
      history_opts.reverse = true
    end

    -- Only apply default limit when no range specified
    if not range or range == "" then
      history_opts.limit = 100
    end

    -- If file_path specified, filter by that file
    if expanded_file_path then
      history_opts.path = git.get_relative_path(expanded_file_path, git_root)
    end

    -- If line range specified, set up for git log -L
    if line_range and history_opts.path then
      history_opts.line_range = line_range
    end

    git.get_commit_list(range or "", git_root, history_opts, function(err, commits)
      if err then
        vim.schedule(function()
          vim.notify("Failed to get commit history: " .. err, vim.log.levels.ERROR)
        end)
        return
      end

      if #commits == 0 then
        vim.schedule(function()
          vim.notify("No commits found in range", vim.log.levels.INFO)
        end)
        return
      end

      vim.schedule(function()
        ---@type SessionConfig
        local session_config = {
          mode = "history",
          git_root = git_root,
          original = path.empty(),
          modified = path.empty(),
          original_revision = nil,
          modified_revision = nil,
          layout = global_opts.layout,
          exit_on_close = global_opts.exit_on_close,
          history_data = {
            commits = commits,
            range = range,
            file_path = history_opts.path,
            base_revision = flags.base,
            line_range = line_range,
          },
        }

        view.create(session_config, "")
      end)
    end)
  end

  -- Resolve the working repo (honors --repo/-C) and open the history view.
  resolve_working_root(global_opts, open_history)
end

local function handle_explorer(revision, revision2, global_opts, pathspec)
  local current_file = vim.api.nvim_buf_get_name(0)

  local function open_explorer(git_root, is_override)
    -- Compute focus_file (relative path to current buffer) for focusing in explorer.
    -- Skip when --repo/-C targets a different repo: the current buffer isn't in it.
    local focus_file = nil
    if current_file ~= "" and not is_override then
      focus_file = git.get_relative_path(current_file, git_root)
    end

    local function process_status(err_status, status_result, original_rev, modified_rev)
      vim.schedule(function()
        if err_status then
          vim.notify(err_status, vim.log.levels.ERROR)
          return
        end

        -- Check if there are any changes (including conflicts)
        local has_conflicts = status_result.conflicts and #status_result.conflicts > 0
        if #status_result.unstaged == 0 and #status_result.staged == 0 and not has_conflicts then
          vim.notify("No changes to show", vim.log.levels.INFO)
          return
        end

        -- Create explorer view with empty diff panes initially

        ---@type SessionConfig
        local session_config = {
          mode = "explorer",
          git_root = git_root,
          original = path.empty(), -- Empty indicates explorer mode placeholder
          modified = path.empty(),
          original_revision = original_rev,
          modified_revision = modified_rev,
          layout = global_opts.layout,
          exit_on_close = global_opts.exit_on_close,
          explorer_data = {
            status_result = status_result,
            focus_file = focus_file, -- Focus on current file if changed
            pathspec = pathspec, -- Scope (#74): preserved so refresh re-applies it
          },
        }

        -- view.create handles everything: tab, windows, explorer, and lifecycle
        -- Empty lines and paths - explorer will populate via first file selection
        view.create(session_config, "")
      end)
    end

    if revision and revision2 then
      -- Compare two revisions
      git.resolve_revision(revision, git_root, function(err_resolve, commit_hash)
        if err_resolve then
          vim.schedule(function()
            vim.notify(err_resolve, vim.log.levels.ERROR)
          end)
          return
        end

        git.resolve_revision(revision2, git_root, function(err_resolve2, commit_hash2)
          if err_resolve2 then
            vim.schedule(function()
              vim.notify(err_resolve2, vim.log.levels.ERROR)
            end)
            return
          end

          git.get_diff_revisions_with_line_stats(commit_hash, commit_hash2, git_root, function(err_status, status_result)
            process_status(err_status, status_result, commit_hash, commit_hash2)
          end, pathspec)
        end)
      end)
    elseif revision then
      -- Resolve revision first, then get diff
      git.resolve_revision(revision, git_root, function(err_resolve, commit_hash)
        if err_resolve then
          vim.schedule(function()
            vim.notify(err_resolve, vim.log.levels.ERROR)
          end)
          return
        end

        -- Get diff between revision and working tree
        git.get_diff_revision_with_line_stats(commit_hash, git_root, function(err_status, status_result)
          process_status(err_status, status_result, commit_hash, "WORKING")
        end, pathspec)
      end)
    else
      -- Get git status (current changes)
      git.get_status_with_line_stats(git_root, function(err_status, status_result)
        -- Pass nil for revisions to enable "Status Mode" in explorer (separate Staged/Unstaged groups)
        process_status(err_status, status_result, nil, nil)
      end, pathspec)
    end
  end

  -- Resolve the working repo (honors --repo/-C) and open the explorer.
  resolve_working_root(global_opts, open_explorer)
end

-- Wrapper for merge-base explorer mode: computes merge-base first, then opens explorer
local function handle_explorer_merge_base(base_rev, target_rev, global_opts, pathspec)
  local current_buf = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buf)
  local cwd = vim.fn.getcwd()
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = current_buf })
  -- A file usually has a buftype of "" so filter out `nofile` or dashboards etc.
  -- --repo/-C overrides the seed so the merge base is computed in that repo.
  local path_for_root = (global_opts and global_opts.repo) or (buftype == "" and current_file ~= "" and current_file or cwd)

  git.get_git_root(path_for_root, function(err_root, git_root)
    if err_root then
      vim.schedule(function()
        vim.notify(err_root, vim.log.levels.ERROR)
      end)
      return
    end

    local actual_target = target_rev or "HEAD"
    git.get_merge_base(base_rev, actual_target, git_root, function(err_mb, merge_base_hash)
      if err_mb then
        vim.schedule(function()
          vim.notify(err_mb, vim.log.levels.ERROR)
        end)
        return
      end

      -- Schedule the explorer call to run in main context (handle_explorer uses nvim_get_current_buf)
      vim.schedule(function()
        if target_rev then
          handle_explorer(merge_base_hash, target_rev, global_opts, pathspec)
        else
          handle_explorer(merge_base_hash, nil, global_opts, pathspec)
        end
      end)
    end)
  end)
end

-- Wrapper for merge-base single-file diff: computes merge-base first, then opens diff
local function handle_git_diff_merge_base(base_rev, target_rev, global_opts)
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file == "" then
    vim.notify("Current buffer is not a file", vim.log.levels.ERROR)
    return
  end

  git.get_git_root(current_file, function(err_root, git_root)
    if err_root then
      vim.schedule(function()
        vim.notify(err_root, vim.log.levels.ERROR)
      end)
      return
    end

    local actual_target = target_rev or "HEAD"
    git.get_merge_base(base_rev, actual_target, git_root, function(err_mb, merge_base_hash)
      if err_mb then
        vim.schedule(function()
          vim.notify(err_mb, vim.log.levels.ERROR)
        end)
        return
      end

      -- Schedule the diff call to run in main context (handle_git_diff uses nvim_buf_get_name)
      vim.schedule(function()
        handle_git_diff(merge_base_hash, target_rev, global_opts)
      end)
    end)
  end)
end

function M.vscode_merge(opts, global_opts)
  global_opts = global_opts or {}
  local args = opts.fargs
  if #args == 0 then
    vim.notify("Usage: :CodeDiff merge <filename>", vim.log.levels.ERROR)
    return
  end

  local filename = args[1]
  -- Strip surrounding quotes if present (from shell escaping in git mergetool)
  filename = filename:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")

  -- Resolve to absolute path
  local full_path = vim.fn.fnamemodify(filename, ":p")

  if vim.fn.filereadable(full_path) == 0 then
    vim.notify("File not found: " .. filename, vim.log.levels.ERROR)
    return
  end

  -- Ensure all required modules are loaded before we start vim.wait
  -- This prevents issues with lazy-loading during the wait loop

  -- For synchronous execution (required by git mergetool), we need to block
  -- until the view is ready. Use vim.wait which processes the event loop.
  local view_ready = false
  local error_msg = nil

  git.get_git_root(full_path, function(err_root, git_root)
    if err_root then
      error_msg = "Not a git repository: " .. err_root
      view_ready = true
      return
    end

    local relative_path = git.get_relative_path(full_path, git_root)

    -- Schedule everything that needs main thread (vim.filetype.match, view.create)
    vim.schedule(function()
      local filetype = vim.filetype.match({ filename = full_path }) or ""

      -- Determine conflict buffer positions based on config
      -- conflict_ours_position controls where :2 (OURS) appears on screen
      local ours_position = config.options.diff.conflict_ours_position or "right"

      -- After conflict_window.lua's win_splitmove(rightbelow=false):
      -- - original_win is on LEFT
      -- - modified_win is on RIGHT
      local original_rev, modified_rev
      if ours_position == "right" then
        original_rev = ":3" -- THEIRS in original_win (LEFT)
        modified_rev = ":2" -- OURS in modified_win (RIGHT)
      else
        original_rev = ":2" -- OURS in original_win (LEFT)
        modified_rev = ":3" -- THEIRS in modified_win (RIGHT)
      end

      ---@type SessionConfig
      local session_config = {
        mode = "standalone",
        git_root = git_root,
        original = path.make_ref(relative_path, git_root),
        modified = path.make_ref(relative_path, git_root),
        original_revision = original_rev,
        modified_revision = modified_rev,
        conflict = true,
        exit_on_close = global_opts.exit_on_close,
      }

      view.create(session_config, filetype, function()
        view_ready = true
      end)
    end)
  end)

  -- Block until view is ready - this allows event loop to process callbacks
  vim.wait(10000, function()
    return view_ready
  end, 10)

  -- Force screen redraw after vim.wait to ensure all windows are visible
  vim.cmd("redraw!")

  if error_msg then
    vim.notify(error_msg, vim.log.levels.ERROR)
  end
end

-- ── Command tree (argparse) ────────────────────────────────────────────────
-- The :CodeDiff grammar is declared once as an argparse Command tree. The
-- handlers reproduce the previous dispatch exactly; revision/file/dir and
-- triple-dot detection stays in the handlers because it touches the filesystem.

-- Translate global flags into the { layout, exit_on_close } table handlers expect.
local function to_global_opts(m)
  local layout
  if m:get_flag("inline") then
    layout = "inline"
  elseif m:get_flag("side_by_side") then
    layout = "side-by-side"
  end
  -- Expand ~ and env vars in the --repo/-C path once, here at the boundary, so
  -- every consumer gets a filesystem-ready seed for git-root resolution.
  local repo = m:get_one("repo")
  repo = repo and repo ~= "" and vim.fn.expand(repo) or nil
  return { layout = layout, exit_on_close = m:get_flag("exit_on_close") or nil, repo = repo }
end

-- Expand % (current file) and ~/env in a path argument.
local function expand_arg_path(p)
  if p == "%" then
    return vim.api.nvim_buf_get_name(0)
  end
  return vim.fn.expand(p)
end

-- Cached git revision candidates (completion fires on every keystroke).
local rev_cache = { candidates = nil, git_root = nil, timestamp = 0 }
local function rev_candidates()
  local now = vim.loop.now() / 1000
  local git_root = git.get_git_root_sync(vim.fn.getcwd())
  if rev_cache.candidates and rev_cache.git_root == git_root and (now - rev_cache.timestamp) < 5 then
    return rev_cache.candidates
  end
  local cands = git.get_rev_candidates(git_root)
  rev_cache.candidates, rev_cache.git_root, rev_cache.timestamp = cands, git_root, now
  return cands
end

-- Completor: git refs, plus their `ref...` merge-base variants.
local function complete_revisions(ctx)
  local lead = ctx.arg_lead or ""
  local base = lead:match("^(.+)%.%.%.$")
  local out = {}
  for _, r in ipairs(rev_candidates()) do
    if base then
      table.insert(out, base .. "..." .. r)
    else
      table.insert(out, r)
      table.insert(out, r .. "...")
    end
  end
  return out
end

-- Completor: file paths.
local function complete_files(ctx)
  return vim.fn.getcompletion(ctx.arg_lead or "", "file")
end

-- Completor: directory paths (for --repo/-C).
local function complete_dirs(ctx)
  return vim.fn.getcompletion(ctx.arg_lead or "", "dir")
end

-- Build the :CodeDiff command tree.
local function build_app()
  local Arg = ap.Arg

  local app = ap
    .Command
    .new("CodeDiff")
    :about("VSCode-style diff view")
    :arg(Arg.flag("inline"):long("--inline"):global(true))
    :arg(Arg.flag("side_by_side"):long("--side-by-side"):global(true))
    :arg(Arg.flag("exit_on_close"):long("--exit-on-close"):global(true))
    -- --repo/-C <path>: operate on the repo containing <path> (root or any subdir)
    -- instead of the current buffer/cwd. Applies to explorer and history modes.
    :arg(
      Arg.new("repo"):long("--repo"):short("-C"):global(true):completor(complete_dirs)
    )
    -- Default action: explorer for the working tree, a revision, or two revisions.
    :arg(Arg.new("rev1"):completor(complete_revisions))
    :arg(Arg.new("rev2"):completor(complete_revisions))
    -- Operands after `--` are git pathspecs (#74); complete them as file paths.
    :trailing(Arg.new("pathspec"):completor(complete_files))
    :handler(function(m)
      local go = to_global_opts(m)
      -- Tokens after `--` are git pathspecs that scope the file list (issue #74).
      local trailing = m:trailing()
      local pathspec = #trailing > 0 and trailing or nil
      local a, b = m:get_one("rev1"), m:get_one("rev2")
      if not a then
        handle_explorer(nil, nil, go, pathspec)
        return
      end
      if b and not pathspec then
        local e1, e2 = vim.fn.expand(a), vim.fn.expand(b)
        if vim.fn.isdirectory(e1) == 1 and vim.fn.isdirectory(e2) == 1 then
          handle_dir_diff(e1, e2, go)
          return
        end
      end
      local base, target = parse_triple_dot(a)
      if base then
        handle_explorer_merge_base(base, target, go, pathspec)
      elseif b then
        handle_explorer(a, b, go, pathspec)
      else
        handle_explorer(a, nil, go, pathspec)
      end
    end)

  app:subcommand(ap.Command.new("file"):arg(Arg.new("a"):completor(complete_revisions)):arg(Arg.new("b"):completor(complete_files)):handler(function(m)
    local go = to_global_opts(m)
    local a, b = m:get_one("a"), m:get_one("b")
    if a and b then
      if vim.fn.filereadable(a) == 1 and vim.fn.filereadable(b) == 1 then
        handle_file_diff(a, b, go)
      else
        handle_git_diff(a, b, go)
      end
    elseif a then
      local base, target = parse_triple_dot(a)
      if base then
        handle_git_diff_merge_base(base, target, go)
      else
        handle_git_diff(a, nil, go)
      end
    else
      vim.notify("Usage: :CodeDiff file <revision> [revision2] OR :CodeDiff file <file_a> <file_b>", vim.log.levels.ERROR)
    end
  end))

  app:subcommand(ap.Command.new("dir"):arg(Arg.new("d1"):completor(complete_files)):arg(Arg.new("d2"):completor(complete_files)):handler(function(m)
    local d1, d2 = m:get_one("d1"), m:get_one("d2")
    if d1 and d2 then
      handle_dir_diff(d1, d2, to_global_opts(m))
    else
      vim.notify("Usage: :CodeDiff dir <dir1> <dir2>", vim.log.levels.ERROR)
    end
  end))

  app:subcommand(
    ap.Command
      .new("history")
      :arg(Arg.new("arg1"):completor(complete_revisions))
      :arg(Arg.new("arg2"):completor(complete_files))
      :arg(Arg.flag("reverse"):long("--reverse"):short("-r"))
      :arg(Arg.new("base"):long("--base"):short("-b"):completor(complete_revisions))
      :handler(function(m)
        local go = to_global_opts(m)
        local flags = { reverse = m:get_flag("reverse"), base = m:get_one("base") }
        local arg1, arg2 = m:get_one("arg1"), m:get_one("arg2")
        local range, file_path
        if arg1 and arg2 then
          range = arg1
          file_path = expand_arg_path(arg2)
        elseif arg1 then
          local expanded = expand_arg_path(arg1)
          if vim.fn.filereadable(expanded) == 1 then
            file_path = expanded
          else
            range = arg1
          end
        end
        local line_range = m:range()
        if line_range and not file_path then
          local buf_name = vim.api.nvim_buf_get_name(0)
          if buf_name ~= "" then
            file_path = buf_name
          else
            vim.notify("Line-range history requires a file buffer", vim.log.levels.ERROR)
            return
          end
        end
        handle_history(range, file_path, flags, line_range, go)
      end)
  )

  app:subcommand(ap.Command.new("merge"):arg(Arg.new("file"):completor(complete_files)):handler(function(m)
    local file = m:get_one("file")
    if not file then
      vim.notify("Usage: :CodeDiff merge <filename>", vim.log.levels.ERROR)
      return
    end
    M.vscode_merge({ fargs = { file } }, to_global_opts(m))
  end))

  app:subcommand(ap.Command.new("install"):handler(function(m)
    local force = m:bang()
    local installer = require("codediff.core.installer")
    if force then
      vim.notify("Reinstalling libvscode-diff...", vim.log.levels.INFO)
    end
    local success, err = installer.install({ force = force, silent = false })
    if success then
      vim.notify("libvscode-diff installation successful!", vim.log.levels.INFO)
    else
      vim.notify("Installation failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end))

  return app
end

local _app
local function get_app()
  _app = _app or build_app()
  return _app
end

-- Tokens the completion engine sees: drop the command name and the partial lead.
local function completion_prior(cmd_line, arg_lead)
  local toks = vim.split(cmd_line, "%s+", { trimempty = true })
  table.remove(toks, 1)
  if arg_lead ~= "" and toks[#toks] == arg_lead then
    table.remove(toks)
  end
  return toks
end

-- Completion entry point shared by :CodeDiff and :VscodeDiff.
function M.complete(arg_lead, cmd_line)
  return ap.complete.complete(get_app(), completion_prior(cmd_line, arg_lead), arg_lead)
end

function M.vscode_diff(opts)
  -- Toggle: close the diff view if the current tab already is one.
  local current_tab = vim.api.nvim_get_current_tabpage()
  if lifecycle.get_session(current_tab) then
    lifecycle.close(current_tab)
    return
  end

  -- Normalize the `install!` alias into the `install` subcommand + bang.
  local fargs, bang = opts.fargs, opts.bang
  if fargs[1] == "install!" then
    fargs = vim.list_slice(fargs, 1, #fargs)
    fargs[1] = "install"
    bang = true
  end

  local _, err = get_app():execute(fargs, {
    bang = bang,
    range = opts.range == 2 and { opts.line1, opts.line2 } or nil,
  })
  if err then
    vim.notify("CodeDiff: " .. tostring(err), vim.log.levels.ERROR)
  end
end

return M
