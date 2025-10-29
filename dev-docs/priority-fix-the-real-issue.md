# THE REAL FIX - Priority System (Not Color Issue!)

## Root Cause Discovered

The char-level highlights were **completely invisible** - even when set to pure WHITE (#FFFFFF)!

This proved it was **NOT a color problem** but a **priority/layering problem**.

## The Bug

### Char highlights used `nvim_buf_add_highlight()`
```lua
vim.api.nvim_buf_add_highlight(bufnr, ns_highlight, hl_group,
                               line_idx, start_col - 1, end_col - 1)
```

**Problem:** `nvim_buf_add_highlight()` is the OLD API that:
- Does NOT support priority
- Does NOT create extmarks
- CANNOT override extmark-based `line_hl_group`

### Line highlights used `nvim_buf_set_extmark()` with `line_hl_group`
```lua
vim.api.nvim_buf_set_extmark(bufnr, ns_highlight, line_idx, 0, {
  line_hl_group = hl_group,
  priority = 100,
})
```

**Result:** Line highlights (extmarks) always won, char highlights (old API) were invisible!

## The Fix

### Convert char highlights to use extmarks with HIGH priority

```lua
vim.api.nvim_buf_set_extmark(bufnr, ns_highlight, line_idx, start_col - 1, {
  end_col = end_col - 1,
  hl_group = hl_group,
  priority = 200,      -- ← HIGHER than line_hl_group (100)
  hl_mode = "combine",  -- Combine with other highlights
})
```

**Result:** Now BOTH use extmarks, and priority system works correctly!

## Priority Hierarchy

```
Priority  Layer        What                    Visibility
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
200       TOP          Char-level highlight    ← WINS! ✅
100       BOTTOM       Line-level background   ← Base layer
```

When both extmarks are on the same position:
- Priority 200 (char) renders ON TOP of priority 100 (line)
- Char highlight is VISIBLE regardless of color choice!

## Before vs After

### Before (Broken):
```lua
Line:  nvim_buf_set_extmark(..., line_hl_group, priority=100)  ← Extmark
Char:  nvim_buf_add_highlight(..., hl_group)                   ← Old API, no priority

Result: Line extmark always visible, char invisible ❌
```

### After (Fixed):
```lua
Line:  nvim_buf_set_extmark(..., line_hl_group, priority=100)  ← Extmark
Char:  nvim_buf_set_extmark(..., hl_group, priority=200)       ← Extmark, HIGHER!

Result: Char renders on top of line ✅
```

## Testing Evidence

With extreme test colors:
- Line: Dark green (#004400)
- Char: Pure white (#FFFFFF)

**Before fix:** White was invisible (old API couldn't override)
**After fix:** White shows up clearly (priority 200 > 100)

## Color Strategy (Now Works!)

Now that priority works, we can use the proper hierarchy:
- **Line (whole): DARK** (70% brightness) → Subtle background
- **Char (text): BRIGHT** (100% brightness) → Stands out

This creates high contrast: Bright text on dark background = **VISIBLE!**

## Code Changes

### File: `lua/vscode-diff/render.lua`

Changed `apply_char_highlight()` function:
- Replaced ALL `nvim_buf_add_highlight()` calls
- With `nvim_buf_set_extmark()` calls
- Added `priority = 200`
- Added `hl_mode = "combine"`

Lines changed: ~40 lines in the function

## Verification

Run this to verify both extmarks exist:

```lua
local ns = vim.api.nvim_create_namespace('vscode-diff-highlight')
local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {details = true})

-- Should see BOTH:
-- 1. line_hl_group (priority 100)
-- 2. hl_group (priority 200)  ← This one wins!
```

## Key Takeaways

1. **Old API vs New API:** `nvim_buf_add_highlight()` doesn't support priority
2. **Extmarks only:** Use `nvim_buf_set_extmark()` for ALL highlights
3. **Priority matters:** Higher priority = rendered on top
4. **Test with extremes:** Use white/black to verify layering, not just color choices

This was a **priority system bug**, not a color selection bug!
