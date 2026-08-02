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

local function entry_key(bufnr, mode, lhs, scope)
  return string.format("%d\0%s\0%s\0%s", bufnr, mode, lhs, scope or "")
end

--- @param name string Diagnostic label (e.g. "session:3")
--- @return table registry
function M.new(name)
  return setmetatable({
    name = name,
    entries = {},
    suspended = false,
    disposed = false,
    -- Generation counter per scope, used to retire claims that a later setup
    -- pass no longer makes, plus the stack of passes currently open.
    scope_gen = {},
    scope_stack = {},
  }, Registry)
end

--- Begin a setup pass for `scope`.
---
--- Keymap setup is re-run whenever a session changes shape (layout toggle,
--- entering or leaving conflict mode, reconfiguration). Without a scope the
--- pass could only add claims, so mappings from the previous shape survived —
--- `gm` after switching to inline, conflict mappings after leaving a merge.
--- Claims made between begin_scope and end_scope are tagged; end_scope
--- releases anything in that scope the pass did not re-claim.
--- @param scope string
function Registry:begin_scope(scope)
  if self.disposed then
    return
  end
  -- A pass that aborted before its end_scope would otherwise leave its name on
  -- the stack forever, so drop any stale entry for this scope first. Claims
  -- made in that window are still attributed to it and will be retired here;
  -- that is acceptable because an aborted setup pass is already a failed state.
  for i = #self.scope_stack, 1, -1 do
    if self.scope_stack[i] == scope then
      table.remove(self.scope_stack, i)
    end
  end
  self.scope_gen[scope] = (self.scope_gen[scope] or 0) + 1
  table.insert(self.scope_stack, scope)
end

--- The pass a claim made right now belongs to.
local function current_scope(self)
  return self.scope_stack[#self.scope_stack]
end

--- Finish a setup pass, releasing claims it did not renew.
---
--- Unwinds to `scope` when given, so a pass that aborted before its own
--- end_scope cannot leave the stack dirty and silently mis-tag later claims.
--- @param scope string|nil Defaults to the innermost open pass
function Registry:end_scope(scope)
  if self.disposed then
    return
  end
  if scope then
    -- Pop until this scope has been closed; anything above it never closed.
    local found = false
    for i = #self.scope_stack, 1, -1 do
      if self.scope_stack[i] == scope then
        found = true
        for _ = #self.scope_stack, i, -1 do
          table.remove(self.scope_stack)
        end
        break
      end
    end
    if not found then
      return
    end
  else
    scope = table.remove(self.scope_stack)
    if not scope then
      return
    end
  end
  local generation = self.scope_gen[scope]
  for key, entry in pairs(self.entries) do
    if entry.scope == scope and entry.generation ~= generation then
      slots.release(self, entry.bufnr, entry.mode, entry.lhs, entry.scope)
      self.entries[key] = nil
    end
  end
end

--- Release every claim belonging to `scope`.
--- Used when a capability goes away entirely, such as leaving conflict mode.
--- @param scope string
function Registry:release_scope(scope)
  if self.disposed then
    return
  end
  for key, entry in pairs(self.entries) do
    if entry.scope == scope then
      slots.release(self, entry.bufnr, entry.mode, entry.lhs, entry.scope)
      self.entries[key] = nil
    end
  end
end

--- Install a mapping owned by this registry.
--- @param bufnr number
--- @param modes string|string[]
--- @param lhs string|string[]|false|nil Configured binding; a list binds the
---   action to every key in it. false/nil silently disables.
--- @param rhs function|string
--- @param opts table|nil Forwarded verbatim to vim.keymap.set (minus buffer)
--- @param meta table|nil { suspendable = boolean, priority = integer, help = boolean }
--- @return boolean claimed
function Registry:claim(bufnr, modes, lhs, rhs, opts, meta)
  if self.disposed then
    return false
  end

  local bindings = normalize.keys(lhs)
  if #bindings == 0 then
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

  for _, resolved in ipairs(bindings) do
    -- `canonical` identifies the slot; `resolved` is the spelling the mapping
    -- APIs accept. Passing the canonical bytes to vim.keymap.set would encode
    -- keys like <2-LeftMouse> and <Down> a second time, leaving a mapping the
    -- real key press can never reach.
    local canonical = normalize.canonical(resolved)
    if canonical then
      for _, mode in ipairs(normalize.modes(modes)) do
        local scope = current_scope(self)
        if slots.claim(self, bufnr, mode, canonical, resolved, rhs, opts, meta.priority, scope) then
          local key = entry_key(bufnr, mode, canonical, scope)
          self.entries[key] = {
            bufnr = bufnr,
            mode = mode,
            lhs = canonical,
            suspendable = suspendable,
            documented = documented,
            scope = scope,
            generation = scope and self.scope_gen[scope] or nil,
          }
          -- A claim added while suspended must not be installed yet.
          if self.suspended and suspendable then
            slots.set_active(self, bufnr, mode, canonical, false, scope)
          end
          claimed = true
        end
      end
    end
  end

  return claimed
end

--- Keys this registry owns that should appear in the help popup.
--- @return table<string, boolean> canonical lhs -> true
function Registry:documented_keys()
  local keys = {}
  for _, entry in pairs(self.entries) do
    if entry.documented and slots.is_live(self, entry.bufnr, entry.mode, entry.lhs, entry.scope) then
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
  for _, resolved in ipairs(normalize.keys(lhs)) do
    local canonical = normalize.canonical(resolved)
    if canonical then
      for _, entry in pairs(self.entries) do
        if entry.lhs == canonical and (mode == nil or entry.mode == mode) and (bufnr == nil or entry.bufnr == bufnr) then
          if slots.is_live(self, entry.bufnr, entry.mode, entry.lhs, entry.scope) then
            return true
          end
        end
      end
    end
  end
  return false
end

--- Release a specific mapping this registry installed.
--- @param bufnr number
--- @param modes string|string[]
--- @param lhs string|string[]|false|nil
function Registry:release(bufnr, modes, lhs)
  if not bufnr then
    return
  end

  for _, resolved in ipairs(normalize.keys(lhs)) do
    local canonical = normalize.canonical(resolved)
    if canonical then
      for _, mode in ipairs(normalize.modes(modes)) do
        -- Release every scope's claim on this key, since the caller names a
        -- mapping rather than a particular setup pass.
        for key, entry in pairs(self.entries) do
          if entry.bufnr == bufnr and entry.mode == mode and entry.lhs == canonical then
            slots.release(self, bufnr, mode, canonical, entry.scope)
            self.entries[key] = nil
          end
        end
      end
    end
  end
end

--- Drop bookkeeping for a buffer that no longer exists, without calling into
--- Neovim: a wiped buffer already took its mappings with it.
--- @param bufnr number
function Registry:forget_buffer(bufnr)
  for key, entry in pairs(self.entries) do
    if entry.bufnr == bufnr then
      self.entries[key] = nil
    end
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
      slots.release(self, entry.bufnr, entry.mode, entry.lhs, entry.scope)
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
      slots.set_active(self, entry.bufnr, entry.mode, entry.lhs, false, entry.scope)
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
      slots.set_active(self, entry.bufnr, entry.mode, entry.lhs, true, entry.scope)
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
    slots.release(self, entry.bufnr, entry.mode, entry.lhs, entry.scope)
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
