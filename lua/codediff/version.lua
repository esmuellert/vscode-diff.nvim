-- Version management - single source of truth for VERSION
local M = {}

-- Load VERSION once at module load time
-- Resolve the plugin root via core.path (single source of truth; it handles
-- relative vs absolute module source paths).
do
  local plugin_root = require("codediff.core.path").get_plugin_root()
  local version_file = plugin_root .. "/VERSION"
  local f = io.open(version_file, "r")
  if f then
    -- Read only the first line and trim whitespace
    local line = f:read("*line")
    f:close()
    if line then
      M.VERSION = line:match("^%s*(.-)%s*$")
    end
  end
end

return M
