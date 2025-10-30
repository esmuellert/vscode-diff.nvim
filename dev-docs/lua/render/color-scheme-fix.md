# Color Scheme Fix - Proper Light/Dark Hierarchy

## Issue

The original colors had inverted brightness:
- "Light" colors were actually **darker** (#1e3a1e, #3a1e1e)
- "Dark" colors were actually **lighter** (#2d6d2d, #6d2d2d)

This caused char-level highlights to be **invisible** because they were lighter than the line backgrounds!

## Solution

### Use Native Neovim Colors + Darkened Variants

1. **Line-level (light):** Link to native `DiffAdd` and `DiffDelete`
   - Adapts to user's color scheme automatically
   - Provides consistent experience with `:diffthis`

2. **Char-level (dark):** Calculate darkened version (60% brightness)
   - Dynamically generated from native colors
   - Always darker than line-level
   - Maintains same color family

## Implementation

```lua
-- Line-level: Use native colors
vim.api.nvim_set_hl(0, "VscodeDiffLineInsert", {
  link = "DiffAdd",  -- Native green
})

vim.api.nvim_set_hl(0, "VscodeDiffLineDelete", {
  link = "DiffDelete",  -- Native red
})

-- Char-level: Darken the native colors
local function darken_color(color)
  local r = math.floor((math.floor(color / 65536) % 256) * 0.6)
  local g = math.floor((math.floor(color / 256) % 256) * 0.6)
  local b = math.floor((color % 256) * 0.6)
  return r * 65536 + g * 256 + b
end

local diff_add = vim.api.nvim_get_hl(0, {name = "DiffAdd"})
vim.api.nvim_set_hl(0, "VscodeDiffCharInsert", {
  bg = darken_color(diff_add.bg),  -- 60% darker
})
```

## Color Brightness Comparison

### Before (Broken)
```
                    Brightness
Line Insert  #1e3a1e     41.8  ← "Light" but actually darker!
Char Insert  #2d6d2d     84.4  ← "Dark" but actually lighter! (INVISIBLE)

Line Delete  #3a1e1e     38.7  ← "Light" but actually darker!
Char Delete  #6d2d2d     70.5  ← "Dark" but actually lighter! (INVISIBLE)
```

### After (Fixed)
```
                    Brightness
Line Insert  #2a4556     62.9  ← Light (from DiffAdd)
Char Insert  #192933     37.4  ← Dark (60% of DiffAdd) ✅

Line Delete  #4b2a3d     54.0  ← Light (from DiffDelete)
Char Delete  #2d1924     32.2  ← Dark (60% of DiffDelete) ✅
```

## Visual Result

**Before:**
```
Line background:  [Light Red]
Char highlight:   [Lighter Red] ← INVISIBLE!
```

**After:**
```
Line background:  [Light Red]
Char highlight:   [Dark Red]   ← VISIBLE! ✅
```

## Benefits

1. **Adaptive:** Works with any color scheme (uses native DiffAdd/DiffDelete)
2. **Correct hierarchy:** Char-level always darker than line-level
3. **Same family:** Darkened colors maintain the same hue
4. **Consistent:** Matches native `:diffthis` experience

## Example Colors (Default Scheme)

**Green (Insert):**
- Line: `#2a4556` (DiffAdd)
- Char: `#192933` (60% darker)

**Red (Delete):**
- Line: `#4b2a3d` (DiffDelete)
- Char: `#2d1924` (60% darker)

## Testing

```vim
:VscodeDiff ../test_playground.txt ../modified_playground.txt
```

You should now see:
- ✅ Light backgrounds on changed lines
- ✅ **Dark overlays** on specific changed characters (visible!)
- ✅ Colors adapt to your color scheme

## Formula: Darkening Colors

Multiply each RGB component by 0.6:
```
R' = R × 0.6
G' = G × 0.6
B' = B × 0.6
```

This maintains the color hue while reducing brightness by 40%.
