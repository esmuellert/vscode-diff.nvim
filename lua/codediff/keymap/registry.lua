-- Per-session keymap registry.
--
-- Owns every mapping a single codediff session installs, so teardown is
-- symmetric with setup. The registry holds no mapping state itself: it records
-- which slots it claimed and delegates arbitration to codediff.keymap.slots.
--
-- Buffer ownership matters for suspend/resume:
--   * borrowed buffers (real files shown in the diff panes) must release their
--     mappings when the user leaves the tab, or codediff's keys would appear
--     on that file everywhere it is opened;
--   * owned buffers (explorer/history panels and other codediff scratch
--     buffers) cannot leak anywhere, so their mappings stay installed until
--     the buffer goes away. Suspending them caused a past regression where
--     panel keys vanished after a tab switch.

local M = {}

local slots = require("codediff.keymap.slots")
local normalize = require("codediff.keymap.normalize")

local Registry = {}
Registry.__index = Registry

local function entry_key(bufnr, mode, lhs)
  return string.format("%d\0%s\0%s", bufnr, mode, lhs)
end

--- @param name string Diagnostic label (e.g. "session:3")
--- @return table registry
function M.new(name)
  return setmetatable({
    name = name,
    entries = {},
    suspended = false,
    disposed = false,
  }, Registry)
end

--- Install a mapping owned by this registry.
--- @param bufnr number
--- @param modes string|string[]
--- @param lhs string|false|nil Configured binding; false/nil silently disables
--- @param rhs function|string
--- @param opts table|nil Forwarded verbatim to vim.keymap.set (minus buffer)
--- @param meta table|nil { suspendable = boolean, priority = integer, help = boolean }
--- @return boolean claimed
function Registry:claim(bufnr, modes, lhs, rhs, opts, meta)
  if self.disposed then
    return false
  end

  local resolved = normalize.resolve(lhs)
  if not resolved then
    return false
  end
  local canonical = normalize.canonical(resolved)
  if not canonical then
    return false
  end
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  meta = meta or {}
  local suspendable = meta.suspendable ~= false
  -- Transparent wrappers over native Vim keys (compact's synced folds) opt out
  -- of the help popup: they do not add a codediff command to discover.
  local documented = meta.help ~= false
  local claimed = false

  for _, mode in ipairs(normalize.modes(modes)) do
    -- `canonical` identifies the slot; `resolved` is the spelling the mapping
    -- APIs accept. Passing the canonical bytes to vim.keymap.set would encode
    -- keys like <2-LeftMouse> and <Down> a second time, leaving a mapping the
    -- real key press can never reach.
    if slots.claim(self, bufnr, mode, canonical, resolved, rhs, opts, meta.priority) then
      local key = entry_key(bufnr, mode, canonical)
      self.entries[key] = {
        bufnr = bufnr,
        mode = mode,
        lhs = canonical,
        suspendable = suspendable,
        documented = documented,
      }
      -- A claim added while suspended must not be installed yet.
      if self.suspended and suspendable then
        slots.set_active(self, bufnr, mode, canonical, false)
      end
      claimed = true
    end
  end

  return claimed
end

--- Keys this registry owns that should appear in the help popup.
--- @return table<string, boolean> canonical lhs -> true
function Registry:documented_keys()
  local keys = {}
  for _, entry in pairs(self.entries) do
    if entry.documented then
      keys[entry.lhs] = true
    end
  end
  return keys
end

--- True when this registry currently owns `lhs`.
--- @param lhs string|false|nil Configured binding
--- @param mode string|nil Restrict to one mode; any mode when omitted
--- @param bufnr number|nil Restrict to one buffer; any buffer when omitted
--- @return boolean
function Registry:owns(lhs, mode, bufnr)
  local resolved = normalize.resolve(lhs)
  if not resolved then
    return false
  end
  local canonical = normalize.canonical(resolved)
  if not canonical then
    return false
  end
  for _, entry in pairs(self.entries) do
    if entry.lhs == canonical and (mode == nil or entry.mode == mode) and (bufnr == nil or entry.bufnr == bufnr) then
      return true
    end
  end
  return false
end

--- Release a specific mapping this registry installed.
--- @param bufnr number
--- @param modes string|string[]
--- @param lhs string|false|nil
function Registry:release(bufnr, modes, lhs)
  local resolved = normalize.resolve(lhs)
  if not resolved or not bufnr then
    return
  end
  local canonical = normalize.canonical(resolved)
  if not canonical then
    return
  end
  for _, mode in ipairs(normalize.modes(modes)) do
    slots.release(self, bufnr, mode, canonical)
    self.entries[entry_key(bufnr, mode, canonical)] = nil
  end
end

--- Release every mapping this registry installed on a buffer.
--- Used when a diff pane swaps to a different file, so the buffer that leaves
--- the session gets its original mappings back immediately.
--- @param bufnr number
function Registry:detach_buffer(bufnr)
  if not bufnr then
    return
  end
  for key, entry in pairs(self.entries) do
    if entry.bufnr == bufnr then
      slots.release(self, entry.bufnr, entry.mode, entry.lhs)
      self.entries[key] = nil
    end
  end
end

--- Release mappings on every buffer except those listed.
--- @param keep table<number, boolean> Set of buffer numbers to retain
function Registry:detach_buffers_except(keep)
  local seen = {}
  for _, entry in pairs(self.entries) do
    if not keep[entry.bufnr] then
      seen[entry.bufnr] = true
    end
  end
  for bufnr in pairs(seen) do
    self:detach_buffer(bufnr)
  end
end

--- Uninstall suspendable mappings, keeping the claims registered.
function Registry:suspend()
  if self.disposed or self.suspended then
    return
  end
  self.suspended = true
  for _, entry in pairs(self.entries) do
    if entry.suspendable then
      slots.set_active(self, entry.bufnr, entry.mode, entry.lhs, false)
    end
  end
end

--- Reinstall previously suspended mappings.
function Registry:resume()
  if self.disposed or not self.suspended then
    return
  end
  self.suspended = false
  for _, entry in pairs(self.entries) do
    if entry.suspendable then
      slots.set_active(self, entry.bufnr, entry.mode, entry.lhs, true)
    end
  end
end

--- Release everything. Idempotent, so repeated cleanup is harmless.
function Registry:dispose()
  if self.disposed then
    return
  end
  self.disposed = true
  for key, entry in pairs(self.entries) do
    slots.release(self, entry.bufnr, entry.mode, entry.lhs)
    self.entries[key] = nil
  end
end

--- Number of mappings currently registered. Test/diagnostic helper.
function Registry:count()
  local total = 0
  for _ in pairs(self.entries) do
    total = total + 1
  end
  return total
end

return M
