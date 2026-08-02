-- Keymap registry facade.
--
-- Every codediff mapping is installed through a per-session registry, which
-- records exactly what it installed and what was there before, so teardown can
-- hand the key back to its previous owner instead of deleting it.
--
-- See codediff.keymap.slots for the ownership rules.

local M = {}

local registry = require("codediff.keymap.registry")
local slots = require("codediff.keymap.slots")
local normalize = require("codediff.keymap.normalize")

--- Create a registry for one session.
--- @param name string Diagnostic label
--- @return table
function M.new(name)
  return registry.new(name)
end

--- Forget every slot for a wiped buffer without touching Neovim.
--- @param bufnr number
function M.forget_buffer(bufnr)
  slots.forget_buffer(bufnr)
end

M.canonical = normalize.canonical
M.resolve = normalize.resolve
M.keys = normalize.keys

--- Live slot count. Test/diagnostic helper.
M.slot_count = slots.count
M.inspect_slot = slots.inspect

return M
