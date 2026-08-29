-- Waiting for both sides of a diff to arrive.
--
-- A diff needs the original and the modified content together, and each side
-- arrives on its own schedule: one may come from a git fetch, the other from a
-- BufReadCmd, and either can finish first. Whichever callback runs last is the
-- one that must start the render -- but a callback only knows about its own
-- side, so something has to remember which sides are still outstanding.
--
-- That bookkeeping was written out by hand at four call sites, twice under the
-- name `pending` and twice under `wait_state`. This is that bookkeeping, once.

local M = {}

--- Wait for every named side, then run `on_ready` exactly once.
---
--- Names are arbitrary labels; the caller reports each one as it lands. An
--- empty list means nothing is outstanding, so `on_ready` runs immediately.
--- Reporting the same name twice, or a name that was never awaited, does
--- nothing -- so a duplicated event cannot render twice.
---
--- @param names string[] Sides to wait for, e.g. { "original", "modified" }
--- @param on_ready function Run once every name has been reported
--- @return table waiter With done(name) and pending()
function M.when_all(names, on_ready)
  local outstanding = {}
  local remaining = 0
  for _, name in ipairs(names) do
    if not outstanding[name] then
      outstanding[name] = true
      remaining = remaining + 1
    end
  end

  -- Reporting a name removes it from `outstanding`, so a side can only be
  -- counted once and this can only reach zero once. No separate "already ran"
  -- flag: nothing can get past the check above to need one.
  local function fire_if_ready()
    if remaining > 0 then
      return
    end
    on_ready()
  end

  fire_if_ready()

  return {
    --- Report that `name` has arrived.
    --- @param name string
    done = function(name)
      if not outstanding[name] then
        return
      end
      outstanding[name] = nil
      remaining = remaining - 1
      fire_if_ready()
    end,

    --- True while any awaited side is still outstanding.
    --- @return boolean
    pending = function()
      return remaining > 0
    end,
  }
end

return M
