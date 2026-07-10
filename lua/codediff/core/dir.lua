-- Directory comparison logic (no git required)
-- Compares two directories and returns a git-like status result
-- WARNING: Synchronous recursive scan - large directory trees may block Neovim
local M = {}

local uv = vim.loop

local function normalize_dir(path)
  local abs = vim.fn.fnamemodify(path, ":p")
  abs = abs:gsub("\\", "/")
  if abs:sub(-1) == "/" then
    abs = abs:sub(1, -2)
  end
  return abs
end

local function scan_dir(root)
  local files = {}

  local function recurse(current, rel_prefix)
    local handle = uv.fs_scandir(current)
    if not handle then
      return
    end

    while true do
      local name, t = uv.fs_scandir_next(handle)
      if not name then
        break
      end

      local abs = current .. "/" .. name
      local rel = rel_prefix ~= "" and (rel_prefix .. "/" .. name) or name

      if t == "directory" then
        recurse(abs, rel)
      elseif t == "file" then
        local stat = uv.fs_stat(abs) or {}
        files[rel] = {
          path = rel,
          abs = abs,
          size = stat.size,
        }
      end
    end
  end

  recurse(root, "")
  return files
end

local function is_modified(a, b)
  if not a or not b then
    return false
  end
  if a.size ~= b.size then
    return true
  end

  local fd_a = uv.fs_open(a.abs, "r", 0)
  if not fd_a then
    return true
  end

  local fd_b = uv.fs_open(b.abs, "r", 0)
  if not fd_b then
    uv.fs_close(fd_a)
    return true
  end

  local offset = 0
  local chunk_size = 65536

  while true do
    local chunk_a = uv.fs_read(fd_a, chunk_size, offset)
    local chunk_b = uv.fs_read(fd_b, chunk_size, offset)

    if chunk_a == nil or chunk_b == nil then
      uv.fs_close(fd_a)
      uv.fs_close(fd_b)
      return true
    end

    if chunk_a ~= chunk_b then
      uv.fs_close(fd_a)
      uv.fs_close(fd_b)
      return true
    end

    if #chunk_a == 0 then
      break
    end

    offset = offset + #chunk_a
  end

  uv.fs_close(fd_a)
  uv.fs_close(fd_b)
  return false
end

-- Stat a single file. Returns a meta table ({ path, abs, size }) for regular
-- files, or nil for anything that is missing or is not a regular file (e.g. a
-- directory or symlink to a directory).
local function stat_file(abs, rel)
  local stat = uv.fs_stat(abs)
  if not stat or stat.type ~= "file" then
    return nil
  end
  return {
    path = rel,
    abs = abs,
    size = stat.size,
  }
end

-- Build a status_result restricted to an explicit list of relative paths.
-- Instead of scanning the trees, each path is stat'd in both roots and
-- classified (A / D / M). This is O(#paths) rather than O(tree), which is the
-- point of the filter: it avoids touching the (potentially huge) rest of the
-- trees. Paths absent from both roots are collected into `missing`.
local function diff_paths(root1, root2, paths)
  local unstaged = {}
  local missing = {}
  local seen = {}

  for _, rel in ipairs(paths) do
    -- Normalize separators and strip any leading "./" or "/" so lookups are
    -- consistent regardless of how the caller spelled the path.
    rel = rel:gsub("\\", "/"):gsub("^%./", ""):gsub("^/+", "")
    if rel ~= "" and not seen[rel] then
      seen[rel] = true

      local meta1 = stat_file(root1 .. "/" .. rel, rel)
      local meta2 = stat_file(root2 .. "/" .. rel, rel)

      if meta1 and meta2 then
        if is_modified(meta1, meta2) then
          table.insert(unstaged, { path = rel, status = "M" })
        end
      elseif meta1 then
        table.insert(unstaged, { path = rel, status = "D" })
      elseif meta2 then
        table.insert(unstaged, { path = rel, status = "A" })
      else
        table.insert(missing, rel)
      end
    end
  end

  return unstaged, missing
end

-- Compare two directories and return a git-like status_result.
-- dir1 = "original", dir2 = "modified"
-- NOTE: Modification detection compares file content with readblob.
-- opts.paths: optional list of relative paths. When provided, only those paths
--   are compared (each stat'd directly rather than scanning the trees). A path
--   missing on one side is a creation/deletion against the other; a path
--   missing on both sides is reported in the returned `missing` list.
function M.diff_directories(dir1, dir2, opts)
  opts = opts or {}
  local root1 = normalize_dir(dir1)
  local root2 = normalize_dir(dir2)

  local result = {
    unstaged = {},
    staged = {},
    conflicts = {}, -- Empty for dir mode, but consistent with git status shape
  }
  local missing = nil

  if opts.paths and #opts.paths > 0 then
    result.unstaged, missing = diff_paths(root1, root2, opts.paths)
  else
    local files1 = scan_dir(root1)
    local files2 = scan_dir(root2)

    local seen = {}

    for path, meta1 in pairs(files1) do
      local meta2 = files2[path]
      if not meta2 then
        table.insert(result.unstaged, {
          path = path,
          status = "D",
        })
      else
        seen[path] = true
        if is_modified(meta1, meta2) then
          table.insert(result.unstaged, {
            path = path,
            status = "M",
          })
        end
      end
    end

    for path, _ in pairs(files2) do
      if not seen[path] then
        table.insert(result.unstaged, {
          path = path,
          status = "A",
        })
      end
    end
  end

  table.sort(result.unstaged, function(a, b)
    return a.path < b.path
  end)

  return {
    status_result = result,
    root1 = root1,
    root2 = root2,
    missing = missing,
  }
end

return M
