-- tests/framework/init.lua
--
-- Public entry point for the codediff.nvim test framework. This module owns
-- the process-level setup: augmenting the global `assert`, installing the
-- busted-style DSL (`describe`, `it`, `before_each`, `after_each`, `pending`),
-- and exposing `run_file(spec)` / `run_and_exit(spec)` for the shell scripts.
--
-- Rationale: mirrors the "own the small dep" pattern already established by
-- `lua/codediff/ui/lib/` (which replaced `nui.nvim` with a ~300 LOC in-tree
-- copy of just the pieces this plugin actually uses). Replacing plenary.nvim
-- required ~500 LOC of pure Lua + Neovim built-ins — no `git clone` on CI, no
-- external network dependency, and the identical `describe/it/assert.*` API
-- means zero changes to any of the 66 existing `*_spec.lua` files.

local M = {}

local installed = false

--- Install framework globals and start collecting tests.
-- Idempotent — calling it more than once is a no-op.
function M.setup()
  if installed then return end
  installed = true

  -- Assertion library replaces `_G.assert`. It is a callable table so the
  -- stdlib form `assert(cond[, msg, ...])` continues to work with full
  -- passthrough of extra return values.
  local a = require("tests.framework.assert")
  _G.assert = a

  -- Some legacy spec files explicitly do `local assert = require("luassert")`.
  -- Route those requires to our in-tree assert module so those specs work
  -- unchanged.
  package.preload["luassert"] = function() return a end

  -- describe/it/before_each/after_each/pending globals
  require("tests.framework.busted").install()
end

--- Run a single spec file. Returns (ok, counts).
function M.run_file(spec_file)
  return require("tests.framework.runner").run_file(spec_file)
end

--- Run a single spec file and exit Neovim with the appropriate exit code.
--- Used by tests/run_tests.{sh,cmd}.
function M.run_and_exit(spec_file)
  return require("tests.framework.runner").run_and_exit(spec_file)
end

return M
