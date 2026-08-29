-- Waiting for both sides of a diff to arrive. Each side comes on its own
-- schedule -- one from a git fetch, the other from BufReadCmd, either first --
-- so whichever callback runs last has to start the render.

local M = {}

--- Wait for every named side, then run `on_ready` exactly once.
--- An empty list runs it immediately. Reporting a name twice, or one that was
--- never awaited, does nothing, so a duplicated event cannot render twice.
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

  -- Reporting a name removes it, so the count can only reach zero once. No
  -- "already ran" flag: nothing can get past that to need one.
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
