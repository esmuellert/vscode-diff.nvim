-- vscode-diff main interface
local M = {}

local ffi = require("ffi")

-- Load the C library
local lib_name = "libdiff_core"
local lib_ext
if ffi.os == "Windows" then
  lib_ext = ".dll"
elseif ffi.os == "OSX" then
  lib_ext = ".dylib"
else
  lib_ext = ".so"
end

-- Try to find the library
local lib_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h") .. "/" .. lib_name .. lib_ext
local lib = ffi.load(lib_path)

-- FFI declarations (must match diff_core.h exactly)
ffi.cdef[[
  // Enums and structs
  typedef enum {
    HL_LINE_INSERT = 0,
    HL_LINE_DELETE = 1,
    HL_CHAR_INSERT = 2,
    HL_CHAR_DELETE = 3
  } HighlightType;

  typedef struct {
    int start_line;
    int start_col;
    int end_line;
    int end_col;
  } CharRange;

  typedef struct {
    int start_line;
    int end_line;
  } LineRange;

  typedef struct {
    CharRange original;
    CharRange modified;
  } RangeMapping;

  typedef struct {
    int line_num;
    int start_col;
    int end_col;
    HighlightType type;
  } CharHighlight;

  typedef struct {
    int line_num;
    HighlightType type;
    bool is_filler;
    int char_highlight_count;
    CharHighlight* char_highlights;
  } LineMetadata;

  typedef struct {
    int line_count;
    LineMetadata* line_metadata;
  } SideRenderPlan;

  typedef struct {
    SideRenderPlan left;
    SideRenderPlan right;
  } RenderPlan;

  // Functions
  RenderPlan* compute_diff(const char** lines_a, int count_a,
                           const char** lines_b, int count_b);
  void free_render_plan(RenderPlan* plan);
  const char* get_version(void);
]]

-- Convert Lua table of strings to C array
local function lua_to_c_strings(tbl)
  local count = #tbl
  local arr = ffi.new("const char*[?]", count)
  for i, str in ipairs(tbl) do
    arr[i - 1] = str
  end
  return arr, count
end

-- Convert C RenderPlan to Lua table
local function c_to_lua_plan(c_plan)
  if c_plan == nil then
    return nil
  end

  local plan = {
    left = {
      line_count = c_plan.left.line_count,
      line_metadata = {}
    },
    right = {
      line_count = c_plan.right.line_count,
      line_metadata = {}
    }
  }

  -- Convert left side
  for i = 0, c_plan.left.line_count - 1 do
    local meta = c_plan.left.line_metadata[i]
    local char_highlights = {}
    for j = 0, meta.char_highlight_count - 1 do
      local ch = meta.char_highlights[j]
      table.insert(char_highlights, {
        line_num = ch.line_num,
        start_col = ch.start_col,
        end_col = ch.end_col,
        type = tonumber(ch.type)
      })
    end

    table.insert(plan.left.line_metadata, {
      line_num = meta.line_num,
      type = tonumber(meta.type),
      is_filler = meta.is_filler,
      char_highlights = char_highlights
    })
  end

  -- Convert right side
  for i = 0, c_plan.right.line_count - 1 do
    local meta = c_plan.right.line_metadata[i]
    local char_highlights = {}
    for j = 0, meta.char_highlight_count - 1 do
      local ch = meta.char_highlights[j]
      table.insert(char_highlights, {
        line_num = ch.line_num,
        start_col = ch.start_col,
        end_col = ch.end_col,
        type = tonumber(ch.type)
      })
    end

    table.insert(plan.right.line_metadata, {
      line_num = meta.line_num,
      type = tonumber(meta.type),
      is_filler = meta.is_filler,
      char_highlights = char_highlights
    })
  end

  return plan
end

-- Public API
function M.get_version()
  return ffi.string(lib.get_version())
end

function M.compute_diff(lines_a, lines_b)
  local c_arr_a, count_a = lua_to_c_strings(lines_a)
  local c_arr_b, count_b = lua_to_c_strings(lines_b)

  local c_plan = lib.compute_diff(c_arr_a, count_a, c_arr_b, count_b)
  local lua_plan = c_to_lua_plan(c_plan)

  lib.free_render_plan(c_plan)

  return lua_plan
end

-- Highlight type constants
M.HL_LINE_INSERT = 0
M.HL_LINE_DELETE = 1
M.HL_CHAR_INSERT = 2
M.HL_CHAR_DELETE = 3

return M
