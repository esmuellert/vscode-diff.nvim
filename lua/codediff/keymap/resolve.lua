-- Decides which action keeps a key when two of them want the same one.
--
-- Remapping an action onto another action's default is the common way this
-- happens: `view.toggle_explorer = "<leader>e"` collides with the default
-- `view.focus_explorer`. Both get bound, the later one wins, and the user sees
-- their own mapping silently do nothing (#357).
--
-- The rule: a key the user chose beats a key that is merely a default. The
-- losing default is dropped rather than rebound elsewhere, so `<leader>e` runs
-- what the user asked for and `focus_explorer` is simply unbound. Deciding it
-- here, once, keeps every call site free of this logic -- a dropped binding
-- comes back as `false`, which they already treat as "not bound".

local M = {}

local config = require("codediff.config")
-- The registry identifies a mapping by its canonical bytes. Reusing that here
-- makes "the same key" mean the same thing in both places.
local normalize = require("codediff.keymap.normalize")

--- Config keys that bind something despite not being in `defaults`: deprecated
--- spellings the code still honours (see the fallback in ui/view/keymaps.lua).
--- Anything else written under `keymaps` binds nothing -- a typo, or an option
--- from an older version -- and must not be able to take a key away from a
--- real action.
local STILL_HONOURED = {
  ["explorer.toggle_stage"] = true,
}

--- Does this config entry actually bind anything?
--- @return boolean
local function is_real_action(scope, name)
  local shipped = config.defaults.keymaps and config.defaults.keymaps[scope]
  if type(shipped) == "table" and shipped[name] ~= nil then
    return true
  end
  return STILL_HONOURED[scope .. "." .. name] == true
end

--- Did the user pick this key, or is it the one codediff ships?
---
--- Read off the config instead of being recorded during setup(): a value that
--- differs from its default can only have come from the user. That needs no
--- extra state to keep in step with `options` -- and `options` is reset
--- wholesale in many places, so a second source of truth would go stale.
---
--- The one thing it cannot see is a user who re-states a default verbatim.
--- Such a key collides with nothing new, so nothing depends on the difference.
--- @return boolean
local function chosen_by_user(scope, name, value)
  local shipped = config.defaults.keymaps and config.defaults.keymaps[scope]
  local default = type(shipped) == "table" and shipped[name] or nil
  return value ~= default
end

--- Spell a canonical key the way the user wrote it in their config, for use in
--- messages. keytrans is missing on older Neovim; this is only ever a
--- diagnostic string, so falling back to the raw bytes is good enough.
--- @return string
local function spell_key(key)
  if vim.fn.exists("*keytrans") == 1 then
    local ok, translated = pcall(vim.fn.keytrans, key)
    if ok and translated ~= "" then
      return translated
    end
  end
  return key
end

-- Clashes already reported. Keymap setup re-runs on every render and fans out
-- across buffers; the message is about the user's config, so it is worth
-- saying once per session rather than once per pass.
local already_warned = {}

--- Tell the user that two keys they chose themselves want the same slot.
--- @param key string
--- @param action_names string[] e.g. { "view.quit", "explorer.refresh" }
local function warn_user_keys_clash(key, action_names)
  table.sort(action_names)
  local token = table.concat(action_names, "\0")
  if already_warned[token] then
    return
  end
  already_warned[token] = true

  vim.schedule(function()
    vim.notify(
      ("[codediff] %s are mapped to the same key %s. Only one of them can work; give the others different keys.")
        :format(table.concat(action_names, ", "), key),
      vim.log.levels.WARN
    )
  end)
end

--- Every action that wants each key, across every scope.
--- Grouped across scopes on purpose: view mappings fan out to all session
--- buffers, so a view key really can land on top of an explorer or history one.
--- @return table<string, table[]> canonical key -> { scope, name, chosen }
local function group_actions_by_key()
  local by_key = {}

  for scope, entries in pairs(config.options.keymaps or {}) do
    if type(entries) == "table" then
      for name, value in pairs(entries) do
        local key = is_real_action(scope, name) and normalize.canonical(value) or nil
        if key then
          by_key[key] = by_key[key] or {}
          table.insert(by_key[key], {
            scope = scope,
            name = name,
            chosen = chosen_by_user(scope, name, value),
          })
        end
      end
    end
  end

  return by_key
end

--- Which default-keyed actions lose their key to one the user chose.
--- @return table<string, table<string, boolean>> scope -> action name -> true
local function find_defaults_that_lose()
  local losers = {}

  for key, actions in pairs(group_actions_by_key()) do
    local user_picked = vim.tbl_filter(function(action)
      return action.chosen
    end, actions)

    if #actions > 1 and #user_picked > 0 then
      for _, action in ipairs(actions) do
        if not action.chosen then
          losers[action.scope] = losers[action.scope] or {}
          losers[action.scope][action.name] = true
        end
      end

      -- Two hand-written keys on one slot carry no signal about which the user
      -- meant, so neither is dropped and the existing order decides. Which one
      -- that leaves working depends on session shape and buffer, so the message
      -- does not pretend to know -- only that one of them will not work.
      if #user_picked > 1 then
        warn_user_keys_clash(
          spell_key(key),
          vim.tbl_map(function(action)
            return action.scope .. "." .. action.name
          end, user_picked)
        )
      end
    end
  end

  return losers
end

--- The keymaps for one scope, with any key lost to a user's choice set to
--- `false` -- which every caller already reads as "not bound".
--- @param scope string "view", "explorer", "conflict" or "history"
--- @return table name -> key, or false where the key was lost
function M.keymaps_for(scope)
  local entries = config.options.keymaps and config.options.keymaps[scope]
  if type(entries) ~= "table" then
    return {}
  end

  local lost = find_defaults_that_lose()[scope]
  if not lost then
    return entries
  end

  local resolved = {}
  for name, value in pairs(entries) do
    if lost[name] then
      resolved[name] = false
    else
      resolved[name] = value
    end
  end
  return resolved
end

--- Every scope at once, for the help popup, which lists them all.
--- @return table<string, table> scope -> entries
function M.all_keymaps()
  local everything = {}
  for scope in pairs(config.options.keymaps or {}) do
    everything[scope] = M.keymaps_for(scope)
  end
  return everything
end

--- Let a clash be reported again. For tests, which reconfigure repeatedly.
function M.forget_warnings()
  already_warned = {}
end

return M
