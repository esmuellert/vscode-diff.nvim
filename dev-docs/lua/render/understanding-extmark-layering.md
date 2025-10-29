# The REAL Color Hierarchy Fix - Understanding Layering

## The Critical Insight

**`line_hl_group` and `hl_group` DON'T OVERRIDE EACH OTHER - They're different layers!**

- `line_hl_group` = Background color for the **entire line** (edge to edge)
- `hl_group` = Highlight for **specific text range**

They both render **simultaneously**. The text highlight appears ON TOP of the line background.

## The Problem

### Original (Wrong) Approach:
```
Line background:  #4b2a3d (brightness 54.0) ← BRIGHT
Text highlight:   #2d1924 (brightness 32.2) ← DARK

Visual result:
[line starts]DARK TEXT[lots of BRIGHT background][line ends]
```

**Why it's invisible:** The dark text gets lost in the bright line background!

## The Solution

### REVERSE THE STRATEGY:

Instead of:
- Line = Light/Bright
- Char = Dark

Do:
- **Line = Dark/Subtle** (background tint)
- **Char = Bright** (text highlight that stands out)

### New Color Hierarchy:
```
Line background:  #1d303c (brightness 43.7) ← DARK/SUBTLE
Text highlight:   #2a4556 (brightness 62.9) ← BRIGHT

Visual result:
[line starts]BRIGHT TEXT[subtle dark background][line ends]
```

**Why it works:** Bright text on dark background = **HIGH CONTRAST** = VISIBLE! ✅

## Implementation

```lua
-- Line-level: DARKER (70% of native DiffAdd/Delete)
function adjust_brightness(color, 0.7)
  -- Makes colors darker and more subtle
end

vim.api.nvim_set_hl(0, "VscodeDiffLineInsert", {
  bg = adjust_brightness(diff_add.bg, 0.7)  -- Darker
})

-- Char-level: BRIGHTER (use full native color)
vim.api.nvim_set_hl(0, "VscodeDiffCharInsert", {
  bg = diff_add.bg  -- Full brightness
})
```

## Color Comparison

### Green (Insert):
| Layer | Color | Brightness | Purpose |
|-------|-------|------------|---------|
| Line (whole) | `#1d303c` | 43.7 | Dark subtle background |
| Char (text) | `#2a4556` | 62.9 | **Bright highlight** ✅ |

Difference: **+19.2 brightness** = visible!

### Red (Delete):
| Layer | Color | Brightness | Purpose |
|-------|-------|------------|---------|
| Line (whole) | `#341d2a` | 37.4 | Dark subtle background |
| Char (text) | `#4b2a3d` | 54.0 | **Bright highlight** ✅ |

Difference: **+16.6 brightness** = visible!

## How Extmarks Layer

```
Layer 1 (bottom):  line_hl_group
                   ┌─────────────────────────────┐
                   │ DARK BACKGROUND            │
                   └─────────────────────────────┘

Layer 2 (top):     hl_group (on text only)
                   ┌──────┐
                   │BRIGHT│ (empty) (empty)
                   └──────┘

Final render:      [BRIGHT][DARK][DARK][DARK]
                    ^^^^^^^ ← This stands out!
```

## VSCode Behavior

VSCode does the **exact same thing**:

1. **Whole line**: Gets a subtle darker tint
   - Shows "this line changed"
   - Not too intrusive

2. **Changed characters**: Get bright highlight
   - Shows "exactly what changed"
   - High contrast, clearly visible

## The Old Bug

```
Old colors:
  Line #2a4556 (bright 62.9)
  Char #192933 (dark 37.4)

Result:
  ┌───────────────────────┐
  │DARK  BRIGHT BRIGHT    │  ← Dark text invisible!
  └───────────────────────┘
```

## The Fix

```
New colors:
  Line #1d303c (dark 43.7)
  Char #2a4556 (bright 62.9)

Result:
  ┌───────────────────────┐
  │BRIGHT DARK DARK DARK  │  ← Bright text visible!
  └───────────────────────┘
```

## Testing

```vim
:VscodeDiff ../test_playground.txt ../modified_playground.txt
```

You should now see:
- ✅ Subtle dark tint on whole changed lines
- ✅ **Bright highlights** on specific changed text
- ✅ High contrast, clearly visible

## Key Takeaways

1. **Layering matters:** `line_hl_group` and `hl_group` both render
2. **Contrast is key:** Bright on dark = visible, dark on bright = invisible
3. **Reverse the logic:** Make line backgrounds subtle, char highlights prominent
4. **Match VSCode:** Subtle line tint + bright char highlight

This is the correct approach for extmark-based diff highlighting!
