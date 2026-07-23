-- argparse: a small, dependency-free command-line argument parser for Neovim
-- Ex-commands, modeled on Rust's clap (Command / Arg / ArgMatches / ArgAction /
-- ValueParser) with Neovim-native adaptations (returns errors instead of
-- exiting, consumes opts.fargs, exposes bang/range, drives :command completion).
--
-- Quick start:
--   local ap = require("codediff.core.argparse")
--   local app = ap.Command.new("CodeDiff")
--     :arg(ap.Arg.flag("inline"):long("--inline"):global(true))
--     :subcommand(
--       ap.Command.new("history")
--         :arg(ap.Arg.new("range"))                         -- positional
--         :arg(ap.Arg.flag("reverse"):long("--reverse"):short("-r"))
--         :handler(function(m) ... end))
--     :handler(function(m) ... end)                          -- default action
--   local matches, err = app:execute(opts.fargs, { bang = opts.bang })
local M = {}

M.Command = require("codediff.core.argparse.command")
M.Arg = require("codediff.core.argparse.arg")
M.action = require("codediff.core.argparse.action")
M.value_parser = require("codediff.core.argparse.value_parser")
M.errors = require("codediff.core.argparse.error")
M.help = require("codediff.core.argparse.help")
M.complete = require("codediff.core.argparse.complete")

-- Convenience constructor.
function M.new(name)
  return M.Command.new(name)
end

return M
