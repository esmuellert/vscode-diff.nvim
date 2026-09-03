-- The :CodeDiff command: argument tree, completion, and entry points.
-- Each subcommand's implementation lives in commands/handlers/.
local M = {}

-- Subcommands available for :CodeDiff
M.SUBCOMMANDS = { "merge", "file", "dir", "history", "install" }

local git = require("codediff.core.git")
local ap = require("codediff.core.argparse")
local lifecycle = require("codediff.ui.lifecycle")
local parse = require("codediff.commands.parse")

local handlers = {
  git_diff = require("codediff.commands.handlers.git_diff"),
  file_diff = require("codediff.commands.handlers.file_diff"),
  dir_diff = require("codediff.commands.handlers.dir_diff"),
  history = require("codediff.commands.handlers.history"),
  explorer = require("codediff.commands.handlers.explorer"),
  explorer_staged = require("codediff.commands.handlers.explorer_staged"),
  merge = require("codediff.commands.handlers.merge"),
}

-- Kept for callers that reach for commands.vscode_merge directly.
M.vscode_merge = handlers.merge.run

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

-- Completor: file paths.
local function complete_files(ctx)
  return vim.fn.getcompletion(ctx.arg_lead or "", "file")
end

-- Completor: directory paths (for --repo/-C).

-- Completor: directory paths (for --repo/-C).
local function complete_dirs(ctx)
  return vim.fn.getcompletion(ctx.arg_lead or "", "dir")
end

-- Build the :CodeDiff command tree.

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
    -- --staged / --cached: show only the diff between the index and [rev1]
    -- (defaulting to HEAD). Mirrors :DiffviewOpen --staged (#352).
    :arg(
      Arg.flag("staged"):long("--staged")
    )
    :arg(Arg.flag("cached"):long("--cached"))
    -- Default action: explorer for the working tree, a revision, or two revisions.
    :arg(Arg.new("rev1"):completor(complete_revisions))
    :arg(Arg.new("rev2"):completor(complete_revisions))
    -- Operands after `--` are git pathspecs (#74); complete them as file paths.
    :trailing(Arg.new("pathspec"):completor(complete_files))
    :handler(function(m)
      local go = parse.to_global_opts(m)
      -- Tokens after `--` are git pathspecs that scope the file list (issue #74).
      local trailing = m:trailing()
      local pathspec = #trailing > 0 and trailing or nil
      local a, b = m:get_one("rev1"), m:get_one("rev2")
      local staged = m:get_flag("staged") or m:get_flag("cached")
      if staged then
        -- Parity with diffview: `--staged` accepts a single optional revision.
        if b then
          vim.notify("--staged accepts at most one revision", vim.log.levels.ERROR)
          return
        end
        if a and parse.parse_triple_dot(a) then
          vim.notify("--staged does not support triple-dot merge-base ranges", vim.log.levels.ERROR)
          return
        end
        handlers.explorer_staged.run(a, go, pathspec)
        return
      end
      if not a then
        handlers.explorer.run(nil, nil, go, pathspec)
        return
      end
      if b and not pathspec then
        local e1, e2 = vim.fn.expand(a), vim.fn.expand(b)
        if vim.fn.isdirectory(e1) == 1 and vim.fn.isdirectory(e2) == 1 then
          handlers.dir_diff.run(e1, e2, go)
          return
        end
      end
      local base, target = parse.parse_triple_dot(a)
      if base then
        handlers.explorer.run_merge_base(base, target, go, pathspec)
      elseif b then
        handlers.explorer.run(a, b, go, pathspec)
      else
        handlers.explorer.run(a, nil, go, pathspec)
      end
    end)

  app:subcommand(ap.Command.new("file"):arg(Arg.new("a"):completor(complete_revisions)):arg(Arg.new("b"):completor(complete_files)):handler(function(m)
    local go = parse.to_global_opts(m)
    local a, b = m:get_one("a"), m:get_one("b")
    if a and b then
      if vim.fn.filereadable(a) == 1 and vim.fn.filereadable(b) == 1 then
        handlers.file_diff.run(a, b, go)
      else
        handlers.git_diff.run(a, b, go)
      end
    elseif a then
      local base, target = parse.parse_triple_dot(a)
      if base then
        handlers.git_diff.run_merge_base(base, target, go)
      else
        handlers.git_diff.run(a, nil, go)
      end
    else
      vim.notify("Usage: :CodeDiff file <revision> [revision2] OR :CodeDiff file <file_a> <file_b>", vim.log.levels.ERROR)
    end
  end))

  app:subcommand(ap.Command.new("dir"):arg(Arg.new("d1"):completor(complete_files)):arg(Arg.new("d2"):completor(complete_files)):handler(function(m)
    local d1, d2 = m:get_one("d1"), m:get_one("d2")
    if d1 and d2 then
      handlers.dir_diff.run(d1, d2, parse.to_global_opts(m))
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
        local go = parse.to_global_opts(m)
        local flags = { reverse = m:get_flag("reverse"), base = m:get_one("base") }
        local arg1, arg2 = m:get_one("arg1"), m:get_one("arg2")
        local range, file_path
        if arg1 and arg2 then
          range = arg1
          file_path = parse.expand_arg_path(arg2)
        elseif arg1 then
          local expanded = parse.expand_arg_path(arg1)
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
        handlers.history.run(range, file_path, flags, line_range, go)
      end)
  )

  app:subcommand(ap.Command.new("merge"):arg(Arg.new("file"):completor(complete_files)):handler(function(m)
    local file = m:get_one("file")
    if not file then
      vim.notify("Usage: :CodeDiff merge <filename>", vim.log.levels.ERROR)
      return
    end
    M.vscode_merge({ fargs = { file } }, parse.to_global_opts(m))
  end))

  app:subcommand(ap.Command.new("install"):handler(function(m)
    local force = m:bang()
    local installer = require("codediff.core.installer.libvscode_diff")
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
