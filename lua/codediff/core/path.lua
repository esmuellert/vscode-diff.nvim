-- Path utilities for finding plugin root
-- This provides a stable way to locate the plugin root directory

local M = {}

-- Cache the plugin root once computed
local _plugin_root = nil

--- Get the plugin root directory
--- Uses multiple fallback strategies:
--- 1. Navigate up from this file's location
--- 2. Search runtimepath for the plugin
---@return string plugin_root Absolute path to plugin root
function M.get_plugin_root()
  if _plugin_root then
    return _plugin_root
  end

  -- Strategy 1: Navigate up from this file
  -- lua/codediff/core/path.lua -> 4 levels up to plugin root.
  -- ":p" first so a relative module source (Neovim's rtp loader can report
  -- "./lua/..." on Windows) still resolves to an absolute plugin root.
  local this_file = debug.getinfo(1, "S").source:sub(2)
  local root = vim.fn.fnamemodify(this_file, ":p:h:h:h:h")

  -- Validate by checking for a known marker file
  if vim.fn.filereadable(root .. "/VERSION") == 1 then
    _plugin_root = root
    return _plugin_root
  end

  -- Strategy 2: Search runtimepath for our plugin
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    if path:match("vscode%-diff%.nvim$") or path:match("vscode%-diff$") or path:match("codediff%.nvim$") or path:match("codediff$") then
      if vim.fn.filereadable(path .. "/VERSION") == 1 then
        _plugin_root = path
        return _plugin_root
      end
    end
  end

  -- Fallback: use the navigation result even if marker not found
  _plugin_root = root
  return _plugin_root
end

-- ---------------------------------------------------------------------------
-- File path references (repo-relative vs absolute)
-- ---------------------------------------------------------------------------

---A resolved file path carrying both forms. Consumers pick the form they need:
--- `.absolute` for identity/dedup and filesystem/buffer operations (`:edit`,
--- `bufadd`, buffer-name comparison), `.relative` for git operations and
--- `codediff://` URIs.
---@class Path
---@field relative string Repo-relative path (forward slashes); "" when not applicable
---@field absolute string Absolute filesystem path (forward slashes); "" when not applicable

--- Normalize path separators to forward slashes.
---@param p string
---@return string
local function to_forward(p)
  return (p:gsub("\\", "/"))
end

--- Remove trailing slashes (but keep a lone "/" root).
---@param p string
---@return string
local function strip_trailing(p)
  if p == "/" then
    return p
  end
  return (p:gsub("/+$", ""))
end

--- Whether a (forward-slashed) path is absolute: POSIX (/…), UNC (//server) or
--- Windows drive-letter (C:/…).
---@param p string
---@return boolean
local function is_absolute(p)
  if p == "" then
    return false
  end
  if p:sub(1, 1) == "/" then
    return true
  end
  if p:match("^%a:/") then
    return true
  end
  return false
end

--- Build a Path from any path form. This is the single place that knows the
--- absolute ⇄ relative mapping.
---
--- Accepts an absolute path, a repo-relative path, or "" (no file). When `root`
--- is given, the missing form is derived from it; the relative form is only
--- populated when the absolute path lives under `root`.
---@param any_path string|nil Absolute path, repo-relative path, or "" / nil
---@param root string|nil Root (git_root or a directory root) used to convert forms
---@return Path
function M.make_ref(any_path, root)
  any_path = any_path or ""
  if any_path == "" then
    return { relative = "", absolute = "" }
  end

  local p = to_forward(any_path)
  local nroot = (root and root ~= "") and strip_trailing(to_forward(root)) or nil

  if is_absolute(p) then
    local absolute = strip_trailing(p)
    local relative = ""
    if nroot then
      if absolute == nroot then
        relative = ""
      elseif absolute:sub(1, #nroot + 1) == nroot .. "/" then
        relative = absolute:sub(#nroot + 2)
      end
    end
    return { relative = relative, absolute = absolute }
  end

  -- Relative input
  if nroot then
    return { relative = p, absolute = nroot .. "/" .. p }
  end

  -- No root: resolve absolute form against the current working directory so
  -- identity/dedup still works; relative form is meaningless without a root.
  local absolute = strip_trailing(to_forward(vim.fn.fnamemodify(any_path, ":p")))
  return { relative = "", absolute = absolute }
end

--- Whether a Path refers to no file.
---@param ref Path|nil
---@return boolean
function M.is_empty(ref)
  return not ref or (ref.absolute == "" and ref.relative == "")
end

--- An empty Path (no file).
---@return Path
function M.empty()
  return { relative = "", absolute = "" }
end

return M
