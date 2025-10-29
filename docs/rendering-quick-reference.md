# Simplified Neovim Diff Rendering - Quick Reference

## Input Example

```
Original:                Modified:
line 1                   line 1
line 2 to delete  →      line 3
line 3                   line 4 added
```

## Diff Result

```javascript
DetailedLineRangeMapping {
    original: LineRange(2, 4),    // Lines 2-3
    modified: LineRange(2, 4),    // Lines 2-3
    innerChanges: [
        Range(2,1,3,1) -> Range(2,1,2,1)  // Deletion of line 2
    ]
}
```

## 3-Step Rendering Process

### Step 1: Line Highlights (Light Colors)

```
Apply to: mapping.original and mapping.modified ranges

Original (Lines 2-3):        Modified (Lines 2-3):
line 1                       line 1
line 2 to delete [RED BG]    line 3 [GREEN BG]
line 3           [RED BG]    line 4 added [GREEN BG]
```

**Code:**
```lua
apply_line_highlights(left_bufnr, mapping.original, "VscodeDiffLineDelete")
apply_line_highlights(right_bufnr, mapping.modified, "VscodeDiffLineInsert")
```

---

### Step 2: Character Highlights (Dark Colors)

```
Apply to: inner_changes with non-empty ranges

Inner change: Range(2,1,3,1) -> Range(2,1,2,1)
- Original: L2:C1-L3:C1 (NOT empty) → Apply dark red to "line 2 to delete\n"
- Modified: L2:C1-L2:C1 (empty) → Skip
```

**Code:**
```lua
if not is_empty_range(inner.original) then
    apply_char_highlight(left_bufnr, inner.original, "VscodeDiffCharDelete", lines)
end
```

**Result:** Dark red overlay on deleted text (may not be visible if same as line bg)

---

### Step 3: Filler Lines

```
Detect: original NOT empty, modified IS empty → Deletion

Calculate:
- Line count = 3 - 2 = 1 (plus 1 if end_col > 1) = 1
- Position = modified.start_line - 1 = 2 - 1 = 1
- Add filler to modified buffer, after line 1
```

**Code:**
```lua
if not orig_empty and mod_empty then
    insert_filler_lines(right_bufnr, after_line = 1, count = 1)
end
```

**Result:**
```
Original:                Modified:
line 1                   line 1
line 2 to delete [RED]   [FILLER] ← Inserted here
line 3           [RED]   line 3 [GREEN]
                         line 4 added [GREEN]
```

---

## Decision Tree

```
For each inner_change:
  
  ┌─ Both empty? ──→ Skip
  │
  ├─ Both non-empty? ──→ Apply char highlights only
  │
  ├─ Original empty, Modified non-empty? ──→ Insertion
  │   └─→ Add filler to Original side
  │       Position: original.start_line - 1
  │
  └─ Original non-empty, Modified empty? ──→ Deletion
      └─→ Add filler to Modified side
          Position: modified.start_line - 1
```

## Helper Function Reference

### `is_empty_range(range)`
```lua
return range.start_line == range.end_line and 
       range.start_col == range.end_col
```

### `is_past_line_content(line_number, column, lines)`
```lua
return column > #lines[line_number]
```
**Use:** Skip line-ending changes (handles \r\n)

### Filler Position Formula
```
Deletion: after_line = modified_range.start_line - 1
Insertion: after_line = original_range.start_line - 1
```

**Why -1?** "after_line = N" means "insert between line N and N+1"

## Quick Test

```lua
local diff = require('vscode-diff.diff')
local render = require('vscode-diff.render')

render.setup_highlights()

local original = {"line 1", "line 2 to delete", "line 3"}
local modified = {"line 1", "line 3", "line 4 added"}

local diff_result = diff.compute_diff(original, modified)
local bufnr_left = vim.api.nvim_create_buf(false, true)
local bufnr_right = vim.api.nvim_create_buf(false, true)

render.render_diff(bufnr_left, bufnr_right, original, modified, diff_result)
-- Should show:
-- - Left: red backgrounds on lines 2-3
-- - Right: green backgrounds on lines 2-3, filler after line 1
```
