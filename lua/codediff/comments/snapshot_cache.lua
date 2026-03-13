-- Persists comment snapshots across CodeDiff toggle/close cycles.
-- Snapshots are keyed by a stable session identity derived from the diff context.
local M = {}

---@type table<string, codediff.comments.Comment[]>
local snapshots = {}

local SNAPSHOT_DIR = vim.fn.stdpath("state") .. "/codediff/snapshots"

--- Escape path separators to produce a flat, human-readable filename component.
---@param s string
---@return string
local function escape(s)
  return (s:gsub("[\\/:]+", "%%"))
end

---@param session_id string
---@return string
local function snapshot_path(session_id)
  return SNAPSHOT_DIR .. "/" .. session_id
end

--- Build a stable, human-readable session identity from diff context fields.
--- Produces a %-escaped flat key: `git_root%%original_rev%%modified_rev`
---@param git_root string?
---@param original_revision string?
---@param modified_revision string?
---@return string session_id
function M.session_id(git_root, original_revision, modified_revision)
  return table.concat({
    escape(git_root or ""),
    escape(original_revision or ""),
    escape(modified_revision or ""),
  }, "%%")
end

--- Build a session ID directly from a session table.
---@param session table
---@return string session_id
function M.session_id_from_session(session)
  return M.session_id(session.git_root, session.original_revision, session.modified_revision)
end

--- Save a snapshot of comments for a session.
---@param session_id string
---@param comments codediff.comments.Comment[]
function M.save(session_id, comments)
  snapshots[session_id] = vim.deepcopy(comments)

  vim.fn.mkdir(SNAPSHOT_DIR, "p")

  local encoded = vim.mpack.encode(comments)
  local path = snapshot_path(session_id)
  local f = io.open(path, "wb")
  if f then
    f:write(encoded)
    f:close()
  end
end

--- Restore a snapshot for a session. Returns nil if no snapshot exists.
--- Checks memory cache first, then disk.
---@param session_id string
---@return codediff.comments.Comment[]?
function M.restore(session_id)
  if snapshots[session_id] then
    return vim.deepcopy(snapshots[session_id])
  end

  local path = snapshot_path(session_id)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()

  if not data or #data == 0 then
    return nil
  end

  local ok, comments = pcall(vim.mpack.decode, data)
  if not ok or type(comments) ~= "table" then
    return nil
  end

  snapshots[session_id] = comments
  return vim.deepcopy(comments)
end

--- Remove a snapshot (e.g., after successful submit).
---@param session_id string
function M.remove(session_id)
  snapshots[session_id] = nil

  local path = snapshot_path(session_id)
  pcall(os.remove, path)
end

--- Override snapshot directory for tests.
---@param dir string
function M._set_dir_for_tests(dir)
  SNAPSHOT_DIR = dir
end

--- Reset for tests.
function M._reset_for_tests()
  snapshots = {}
end

return M
