# Final Rendering Fix - Whole Line Highlights & Clean Fillers

## Issues Fixed

### Issue #1: Line Highlights Not Showing (Missing Whole-Line Background)

**Problem:**
- Used `end_line + end_col` which doesn't create whole-line background
- Light color highlights were completely missing

**Solution:**
Use `line_hl_group` parameter in extmarks:
```lua
vim.api.nvim_buf_set_extmark(bufnr, ns_highlight, line_idx, 0, {
  line_hl_group = hl_group,  -- This highlights the entire line!
  priority = 100,
})
```

**Why it works:**
- `line_hl_group` is specifically designed for whole-line backgrounds
- It extends the highlight to the full window width
- It includes trailing space after text
- This is the same method used by `:set cursorline`

### Issue #2: Ugly Diagonal Slash Pattern

**Problem:**
- Filler lines showed "/ / / / /" pattern across entire line
- Looked cluttered and ugly
- Not similar to native Neovim or diffview.nvim

**Solution:**
Use simple single space with background color:
```lua
table.insert(virt_lines_content, {{" ", "VscodeDiffFiller"}})
```

**Why it works:**
- The `VscodeDiffFiller` highlight group has a background color
- Virtual lines inherit the highlight background
- Creates a clean, subtle gray bar
- Similar to diffview.nvim's approach

## Visual Result

**Before (Broken):**
```
Left:                          Right:
line 1                         line 1
line 2 to delete [NO BG!]      / / / / / / / [UGLY]
line 3           [NO BG!]      line 3
/ / / / / / / /  [UGLY]        line 4 added
```

**After (Fixed):**
```
Left:                          Right:
line 1                         line 1
line 2 to delete [RED BG]      [GRAY BAR - CLEAN]
line 3           [RED BG]      line 3      [GREEN BG]
[GRAY BAR - CLEAN]             line 4 added[GREEN BG]
```

## Code Changes

### 1. Line Highlight Function
```lua
-- OLD (broken)
vim.api.nvim_buf_set_extmark(bufnr, ns_highlight, line_idx, 0, {
  end_line = line_idx + 1,
  end_col = 0,
  hl_group = hl_group,
})

-- NEW (works!)
vim.api.nvim_buf_set_extmark(bufnr, ns_highlight, line_idx, 0, {
  line_hl_group = hl_group,  -- Highlights entire line width
  priority = 100,
})
```

### 2. Filler Lines
```lua
-- OLD (ugly)
local line_text = "/ / / / / / / / ..."
table.insert(virt_lines_content, {{line_text, "VscodeDiffFiller"}})

-- NEW (clean)
table.insert(virt_lines_content, {{" ", "VscodeDiffFiller"}})
```

## Neovim Extmark Highlight Parameters

| Parameter | Effect | Use Case |
|-----------|--------|----------|
| `hl_group` | Highlights text only | Character-level changes |
| `line_hl_group` | Highlights entire line width | Line-level backgrounds |
| `hl_eol` | Extends `hl_group` to EOL | Doesn't work well for full width |
| `end_line + end_col` | Range highlight | Text ranges, not full lines |

## Key Learnings

1. **For whole-line backgrounds:** Use `line_hl_group` (same as cursorline)
2. **For text-only highlights:** Use `hl_group` with start/end positions
3. **For virtual lines:** Simple content works best (let highlight do the styling)
4. **Priority matters:** Line highlights should have lower priority than char highlights

## Testing

```vim
:VscodeDiff ../test_playground.txt ../modified_playground.txt
```

**Expected:**
- ✅ Red background on deleted lines (whole line width)
- ✅ Green background on added lines (whole line width)
- ✅ Gray bars for filler lines (clean, no slashes)
- ✅ Dark red/green on char-level changes (overlaid on light backgrounds)

## Compatibility

This approach is:
- ✅ Native Neovim (no hacks)
- ✅ Similar to diffview.nvim
- ✅ Similar to `:diffthis` behavior
- ✅ Works with all color schemes
