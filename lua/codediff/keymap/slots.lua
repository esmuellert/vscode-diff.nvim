-- Global mapping-slot arbiter.
--
-- A "slot" is one concrete Neovim mapping: (bufnr, mode, canonical lhs).
-- Every slot remembers the buffer-local mapping that existed before codediff
-- first touched it, and the set of claims currently competing for it.
--
-- Invariants:
--   * The pre-existing mapping is snapshotted exactly once, on first claim.
--   * It is handed back when the last claim is released.
--   * If no buffer-local mapping existed, codediff's mapping is deleted so the
--     global/default binding becomes visible again.
--   * If another plugin replaces codediff's mapping while it is installed, the
--     foreign mapping wins: codediff neither reinstalls nor restores over it.
--
-- Multiple sessions may claim the same slot (the same real file can be open in
-- two diff tabs). Claims are reference-counted so teardown of one session
-- cannot destroy another session's mapping or the user's original.

local M = {}

local normalize = require("codediff.keymap.normalize")

-- slots[bufnr][mode][lhs] = slot
local slots = {}

--- @class CodeDiffKeymapClaim
--- @field owner table Identity of the claiming registry
--- @field rhs function|string Callback or right-hand side
--- @field opts table Options forwarded verbatim to vim.keymap.set
--- @field priority integer Higher wins; ties resolve to the newest claim
--- @field active boolean Suspended claims stay registered but uninstalled

local function slot_table(bufnr, mode, create)
  local by_mode = slots[bufnr]
  if not by_mode then
    if not create then
      return nil
    end
    by_mode = {}
    slots[bufnr] = by_mode
  end
  local by_lhs = by_mode[mode]
  if not by_lhs then
    if not create then
      return nil
    end
    by_lhs = {}
    by_mode[mode] = by_lhs
  end
  return by_lhs
end

--- Read the mapping currently installed for a slot, in buffer context.
local function read_current(bufnr, mode, lhs)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local ok, result = pcall(vim.api.nvim_buf_call, bufnr, function()
    return vim.fn.maparg(lhs, mode, false, true)
  end)
  if not ok or type(result) ~= "table" or next(result) == nil then
    return nil
  end
  return result
end

--- True when `current` is a buffer-local mapping (not a global fallback).
local function is_buffer_local(current)
  return current ~= nil and current.buffer == 1
end

local function drop_slot(slot)
  local by_lhs = slot_table(slot.bufnr, slot.mode, false)
  if by_lhs then
    by_lhs[slot.key] = nil
  end
  local by_mode = slots[slot.bufnr]
  if by_mode then
    local empty = true
    for _, tbl in pairs(by_mode) do
      if next(tbl) ~= nil then
        empty = false
        break
      end
    end
    if empty then
      slots[slot.bufnr] = nil
    end
  end
end

local function install(slot, claim)
  local rhs = claim.rhs
  if type(rhs) == "function" then
    -- Wrap in a per-claim dispatcher so the installed mapping is identifiable
    -- by function identity even when two claims share the same handler.
    if not claim.dispatcher then
      claim.dispatcher = function(...)
        return claim.rhs(...)
      end
    end
    rhs = claim.dispatcher
  end

  local opts = vim.tbl_extend("force", claim.opts or {}, { buffer = slot.bufnr })
  local ok = pcall(vim.keymap.set, slot.mode, slot.lhs, rhs, opts)
  if ok then
    slot.applied = claim
  else
    slot.applied = nil
  end
end

--- Compare two mapping descriptions for identity.
local function same_map(a, b)
  if not a or not b then
    return false
  end
  if a.callback ~= nil or b.callback ~= nil then
    return a.callback == b.callback
  end
  return a.rhs == b.rhs
end

--- True when the mapping currently installed is the one this slot applied.
local function installed_is_ours(slot)
  local claim = slot.applied
  if not claim then
    return false
  end
  local current = read_current(slot.bufnr, slot.mode, slot.lhs)
  if not is_buffer_local(current) then
    return false
  end
  local expected = claim.dispatcher or claim.rhs
  if type(expected) == "function" then
    return current.callback == expected
  end
  return current.rhs == expected
end

--- True when codediff may take this slot: either nothing buffer-local is
--- installed, or what is installed is the snapshot we previously handed back.
local function slot_is_free_for_us(slot)
  local current = read_current(slot.bufnr, slot.mode, slot.lhs)
  if not is_buffer_local(current) then
    return true
  end
  return slot.saved ~= false and same_map(current, slot.saved)
end

--- Hand the slot back to whatever owned it before codediff.
local function restore(slot)
  if not vim.api.nvim_buf_is_valid(slot.bufnr) then
    slot.applied = nil
    return
  end
  if slot.saved then
    pcall(vim.api.nvim_buf_call, slot.bufnr, function()
      vim.fn.mapset(slot.mode, false, slot.saved)
    end)
  else
    pcall(vim.keymap.del, slot.mode, slot.lhs, { buffer = slot.bufnr })
  end
  slot.applied = nil
end

--- Highest-priority active claim; ties resolve to the most recent claim.
local function winner(slot)
  local best, best_index
  for index, claim in ipairs(slot.claims) do
    if claim.active then
      if not best or claim.priority > best.priority or (claim.priority == best.priority and index > best_index) then
        best, best_index = claim, index
      end
    end
  end
  return best
end

--- Bring the real Neovim mapping in line with the slot's claims.
--- The slot survives as long as any claim is registered, even when every claim
--- is suspended, because it holds the snapshot needed to restore on resume.
local function reconcile(slot)
  if not vim.api.nvim_buf_is_valid(slot.bufnr) then
    drop_slot(slot)
    return
  end

  -- Ownership check: if what is installed is no longer the mapping we put
  -- there, another plugin (or the user) has taken over. Stand down for good.
  if slot.applied and not installed_is_ours(slot) then
    slot.displaced = true
    slot.applied = nil
  end

  local win = winner(slot)

  if slot.displaced then
    -- Never reinstall over, or restore across, a foreign mapping.
    if #slot.claims == 0 then
      drop_slot(slot)
    end
    return
  end

  if win then
    if slot.applied ~= win then
      if slot.applied or slot_is_free_for_us(slot) then
        install(slot, win)
      else
        -- Something else claimed the key while we were suspended.
        slot.displaced = true
        slot.applied = nil
      end
    end
    return
  end

  if slot.applied then
    restore(slot)
  end
  if #slot.claims == 0 then
    drop_slot(slot)
  end
end

local function find_claim(slot, owner)
  for index, claim in ipairs(slot.claims) do
    if claim.owner == owner then
      return index, claim
    end
  end
  return nil
end

--- Claim a slot for `owner`, snapshotting any pre-existing buffer-local map.
--- Re-claiming with the same owner replaces that owner's previous claim, which
--- is what happens when a session re-runs its keymap setup after a re-render.
---
--- `key` identifies the slot; `lhs` is what Neovim is asked to map. They differ
--- for keys such as `<2-LeftMouse>` and `<Down>`, whose canonical form contains
--- K_SPECIAL bytes that the mapping APIs would encode a second time.
--- @param owner table
--- @param bufnr number
--- @param mode string
--- @param key string Canonical (already expanded) key sequence, used as identity
--- @param lhs string Key sequence in the form the mapping APIs accept
--- @param rhs function|string
--- @param opts table|nil Forwarded verbatim to vim.keymap.set
--- @param priority integer|nil
--- @return boolean claimed
function M.claim(owner, bufnr, mode, key, lhs, rhs, opts, priority)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) or not key or not lhs then
    return false
  end

  local by_lhs = slot_table(bufnr, mode, true)
  local slot = by_lhs[key]

  if not slot then
    local current = read_current(bufnr, mode, lhs)
    slot = {
      bufnr = bufnr,
      mode = mode,
      key = key,
      lhs = lhs,
      -- Only buffer-local mappings are ours to restore. A global mapping must
      -- never be recreated as a buffer-local one.
      saved = is_buffer_local(current) and current or false,
      claims = {},
    }
    by_lhs[key] = slot
  end

  local existing_index = find_claim(slot, owner)
  if existing_index then
    table.remove(slot.claims, existing_index)
  end

  table.insert(slot.claims, {
    owner = owner,
    rhs = rhs,
    opts = opts or {},
    priority = priority or 0,
    active = true,
  })

  reconcile(slot)
  return true
end

--- Release `owner`'s claim on a slot.
--- @param key string Canonical key sequence used as slot identity
function M.release(owner, bufnr, mode, key)
  local by_lhs = slot_table(bufnr, mode, false)
  local slot = by_lhs and by_lhs[key]
  if not slot then
    return
  end

  local index = find_claim(slot, owner)
  if index then
    table.remove(slot.claims, index)
  end

  reconcile(slot)
end

--- Suspend or resume `owner`'s claim without forgetting it.
--- @param key string Canonical key sequence used as slot identity
function M.set_active(owner, bufnr, mode, key, active)
  local by_lhs = slot_table(bufnr, mode, false)
  local slot = by_lhs and by_lhs[key]
  if not slot then
    return
  end

  local _, claim = find_claim(slot, owner)
  if not claim or claim.active == active then
    return
  end
  claim.active = active

  reconcile(slot)
end

--- Forget every slot for a buffer without touching Neovim.
--- For BufWipeout: the buffer and its mappings are already gone.
function M.forget_buffer(bufnr)
  slots[bufnr] = nil
end

--- Number of live slots. Test/diagnostic helper.
function M.count()
  local total = 0
  for _, by_mode in pairs(slots) do
    for _, by_lhs in pairs(by_mode) do
      for _ in pairs(by_lhs) do
        total = total + 1
      end
    end
  end
  return total
end

--- Inspect a slot. Test/diagnostic helper.
function M.inspect(bufnr, mode, lhs)
  local by_lhs = slot_table(bufnr, mode, false)
  return by_lhs and by_lhs[normalize.canonical(lhs) or lhs] or nil
end

--- Drop all state. Test helper only.
function M.reset()
  slots = {}
end

return M
