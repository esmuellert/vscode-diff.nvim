# Performance & Timeout Control

This plugin provides high-quality character-level diff highlighting similar to VSCode. To ensure fast response times even with large files, it includes an intelligent timeout mechanism that automatically balances speed and detail.

## How It Works

### Native Diff Computation

The diff algorithm works in three stages:

1. **Line-level diff** - Compares entire lines to find which lines changed
2. **Line matching** - Determines which changed lines correspond to each other
3. **Character-level refinement** - Computes exactly what characters differ in matched lines

All stages share one timeout budget for the complete diff computation. See [Native line matching](../README.md#native-line-matching) for the available matching strategies.

### Why Timeout Works Well

Here's the key insight: **useful character diffs are naturally fast**.

Changes where character-level detail matters (variable renames, small edits) typically complete in milliseconds. Changes where character detail doesn't matter much (massive insertions, complete rewrites) take longer.

The timeout naturally filters based on usefulness - fast useful analysis completes, slow less-useful analysis times out.

## Why Timeout Control Matters

Without timeout, some diffs (like comparing files with large insertions) can take multiple seconds. With timeout, you set the maximum wait time.

The timeout works well because it aligns with usefulness:
- Small, meaningful changes → fast analysis → completes before timeout
- Large, less-useful changes → slow analysis → times out gracefully

Even a short timeout (100ms) captures most useful character detail while keeping overall diff time predictable.

## Performance Comparison

Typical large file diff (1150 → 2352 lines):

| Timeout | Time | Character Detail | vs Git |
|---------|------|------------------|--------|
| 5000ms (default) | 1.2s | Full detail | 12x slower |
| 1000ms (fast) | 0.6s | Most detail | 6x slower |
| 100ms (minimal) | 0.4s | Useful detail | 4x slower |
| Git diff | 0.1s | None | Baseline |

Even at 100ms, you'll see meaningful character-level highlighting where it matters most. Lower timeouts primarily skip the expensive cases that don't benefit much from character detail anyway.

## Configuration

### Default (Quality Priority)

```lua
require("codediff").setup({
  diff = {
    max_computation_time_ms = 5000,  -- 5 seconds (VSCode default)
  }
})
```

**Use when**: You want maximum detail and don't mind occasional 1-2 second waits on huge diffs.

### Fast Mode (Speed Priority)

```lua
require("codediff").setup({
  diff = {
    max_computation_time_ms = 1000,  -- 1 second
  }
})
```

**Use when**: You want fast response times with minimal quality loss (99% detail retained).

**Recommended for**: Most users, especially those with large codebases.

### Minimal Timeout Mode

```lua
require("codediff").setup({
  diff = {
    max_computation_time_ms = 100,  -- 100ms
  }
})
```

**Use when**: You prioritize speed.

**Result**: You'll still see character-level detail in most places - the timeout primarily skips expensive edge cases.



## Key Benefits

### 1. Better Quality Than Git Diff

You get character-level detail that Git doesn't provide, at the cost of being several times slower. The quality improvements come from more sophisticated algorithms.

### 2. Natural Optimization

The timeout aligns well with usefulness - changes where character detail matters tend to be fast, while changes where it matters less tend to be slow. This means even shorter timeouts capture most useful detail.

### 3. Predictable Performance

Set your maximum wait time and the plugin respects it. No surprises or hangs, even with large files.

## When to Adjust Timeout

**Lower timeout (500-1000ms)** if you frequently work with large diffs and want faster response.

**Higher timeout (5000ms+)** if you want maximum detail and don't mind occasional waits.

**Default (5000ms)** balances quality and speed for most use cases.

## Technical Details

The timeout is shared across line alignment, line matching, character refinement, and move detection. It applies to the complete diff computation rather than restarting for each changed region.

This means:
- Fast regions complete and provide full detail
- When the deadline expires, remaining refinement is skipped and line-level changes are preserved
- The timeout value doesn't need to be perfect - it naturally adapts to the complexity of your changes



## Recommendations

**For most users**:
```lua
max_computation_time_ms = 1000  -- Fast, 99% quality
```

**For power users with large files**:
```lua
max_computation_time_ms = 500  -- Very fast, 95% quality
```

**For detail-oriented users**:
```lua
max_computation_time_ms = 5000  -- Default, 100% quality
```

## Summary

Timeout control keeps diff computation responsive by allowing you to set a maximum wait time. Since useful character changes tend to be fast while less-useful ones are slow, even moderate timeouts capture most of the useful detail.

You trade speed for quality compared to basic tools like Git diff - the algorithm is more sophisticated but takes longer. The timeout mechanism gives you control over this trade-off with a single parameter.
