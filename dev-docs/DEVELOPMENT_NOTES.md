# Development Notes

**Created**: 2024-10-23  
**Status**: Active Development

## Quick Reference

### Project Status

**MVP**: ✅ **Complete and Ready to Ship**

**Core Features**:
- ✅ Line-level diff (LCS algorithm)
- ✅ Character-level diff (Myers algorithm)  
- ✅ Filler line generation
- ✅ Two-level highlighting
- ✅ Side-by-side layout

**Parity Assessment**:
- ✅ Rendering mechanism: Full parity with VSCode
- ⚠️ Diff algorithm: LCS (vs VSCode's Myers) - functionally equivalent
- ✅ Visual presentation: Matches VSCode exactly
- ✅ Filler lines: Working correctly

### Testing

```bash
# Run all tests
make test

# Run with verbose mode
nvim --headless -c "luafile tests/e2e_test.lua" -- -v
nvim --headless -c "luafile tests/test_filler.lua" -- -v
```

### Key Files
- **C Core**: `../c-diff-core/diff_core.c`
- **Lua Renderer**: `../lua/vscode-diff/init.lua`
- **Implementation Spec**: `../VSCODE_DIFF_MVP_IMPLEMENTATION_PLAN.md`
- **Render Plan Spec**: `../docs/RENDER_PLAN.md`

## Architecture Summary

### Data Flow

```
Input Files → C compute_diff() → RenderPlan → Lua Renderer → Neovim Buffers
```

### Render Plan Structure

The **RenderPlan** is the core data structure containing:
- `left` and `right` SideRenderPlans
- Each side has `line_metadata[]` with:
  - `line_num`: Original line number (1-indexed, -1 for filler)
  - `type`: Highlight type (INSERT/DELETE)
  - `is_filler`: Whether this is an empty alignment line
  - `char_highlights[]`: Character-level diff regions

See `../docs/RENDER_PLAN.md` for complete specification.

### Verbose Output

Enable verbose mode to see internal diff computation:

```lua
local diff = require("vscode-diff")
diff.set_verbose(true)
```

Output format:
- **[LUA]** prefix (magenta): Lua layer operations
- **[C-CORE]** prefix (cyan): C core render plan
- Color-coded line types (green=insert, red=delete)
- Character highlight ranges shown with `↳` symbol

## Historical Notes

### 2024-10-22: Filler Line Fix

**Problem**: Filler lines weren't working for basic insertion case  
**Root Cause**: Naive line-by-line comparison incorrectly classified changes  
**Solution**: Implemented LCS-based diff algorithm  
**Result**: Filler lines now work correctly, matching VSCode behavior

### 2024-10-23: Verbose Output Redesign

**Changes**:
- Removed `g_verbose` from C core
- C verbose output only triggered by explicit Lua call
- Added structured output format with box drawing
- Color-coded output (when TTY supports it)
- Clear [C-CORE] vs [LUA] prefixes
- Character highlights shown with arrows

## VSCode Parity Notes

### What We Match

1. **Visual Output**: Side-by-side layout with identical coloring
2. **Filler Lines**: Empty lines for alignment (using Neovim virtual lines)
3. **Two-Level Highlighting**: Line-level + character-level
4. **Character Diff Algorithm**: Myers (same as VSCode)

### Known Differences

1. **Line Diff Algorithm**: LCS vs Myers
   - Both produce minimal edit distances
   - Results are functionally equivalent in practice
   - May differ in edge cases with multiple equivalent solutions

2. **Scroll Synchronization**: Not implemented (not in MVP scope)

3. **Move Detection**: Not implemented (not in MVP scope)

### VSCode Source References

- Diff Algorithm: `src/vs/base/common/diff/diff.ts` (Myers)
- Diff Widget: `src/vs/editor/browser/widget/diffEditorWidget.ts`
- Decorations: `src/vs/workbench/contrib/scm/browser/dirtydiffDecorator.ts`

GitHub: https://github.com/microsoft/vscode

## Implementation Checklist

### Core Functionality ✅
- [x] Compute line-level diff (LCS)
- [x] Compute character-level diff (Myers)
- [x] Generate filler lines for alignment
- [x] Build RenderPlan structure
- [x] Apply line-level highlights
- [x] Apply character-level highlights
- [x] Handle edge cases (empty files, identical files)

### Testing ✅
- [x] Unit tests (C core)
- [x] E2E tests (full pipeline)
- [x] Filler line tests
- [x] Verbose mode testing

### Documentation ✅
- [x] Implementation plan (MVP spec)
- [x] Render plan specification
- [x] Development notes (this file)
- [x] Code comments

## Future Enhancements (Post-MVP)

1. **Performance**:
   - Optimize for large files (>10K lines)
   - Incremental diff updates

2. **Features**:
   - Move detection (VSCode's intelligent relocation tracking)
   - Synchronized scrolling
   - Inline diff mode

3. **Algorithm**:
   - Optional Myers algorithm for line diff (100% VSCode parity)
   - Patience diff variant
   - Histogram diff

## Debugging Tips

### Enable Verbose Mode

```lua
local diff = require("vscode-diff")
diff.set_verbose(true)
local plan = diff.compute_diff(lines_a, lines_b)
```

### Inspect Render Plan

The render plan shows:
- Each line's position in final buffer
- Original line number
- Highlight type
- Whether it's a filler line
- Character-level highlights

### Common Issues

**Issue**: "Filler lines not appearing"  
**Check**: Ensure line types are correctly set (INSERT on opposite side)

**Issue**: "Character highlights wrong"  
**Check**: Verify start_col/end_col are 0-indexed (inclusive/exclusive)

**Issue**: "Colors not showing"  
**Check**: Highlight groups defined in your color scheme

## Performance Notes

### Current Performance

- **Line diff**: O(n*m) where n,m are line counts
- **Char diff**: O(k*l) where k,l are character counts per line
- **Memory**: O(n+m) for render plan

### Optimization Opportunities

1. **Early termination**: Skip char diff for identical lines
2. **Chunk processing**: Process large files in sections
3. **Caching**: Reuse results for unchanged regions

## Maintenance

### Update Checklist

When modifying the diff algorithm:
1. Update tests to cover new cases
2. Run verbose mode to verify render plan
3. Check parity with VSCode on same input
4. Update documentation if behavior changes

### Code Style

- **C**: Follow K&R style, use descriptive names
- **Lua**: Follow Neovim plugin conventions
- **Comments**: Explain "why", not "what"

---

**Last Updated**: 2024-10-23  
**Maintainer**: vscode-diff.nvim project
