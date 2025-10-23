# Render Plan Specification

**Version**: 1.0  
**Date**: 2024-10-23

## Overview

The **Render Plan** is the core data structure that describes how to visually present differences between two text buffers in a side-by-side diff view. It contains all information needed to:

1. Display content in left and right buffers
2. Apply line-level highlights (insertions/deletions)
3. Apply character-level highlights (fine-grained changes)
4. Insert filler lines for alignment

## Structure

```
RenderPlan
├── left: SideRenderPlan      (left buffer instructions)
└── right: SideRenderPlan     (right buffer instructions)

SideRenderPlan
├── line_count: int           (total lines to display)
└── line_metadata: Array<LineMetadata>

LineMetadata
├── line_num: int             (original line number, 1-indexed; -1 for filler)
├── type: HighlightType       (line-level highlight type)
├── is_filler: bool           (whether this is an empty alignment line)
├── char_highlight_count: int (number of character highlights)
└── char_highlights: Array<CharHighlight>

CharHighlight
├── start_col: int            (start column, 0-indexed inclusive)
├── end_col: int              (end column, 0-indexed exclusive)
└── type: HighlightType       (character-level highlight type)
```

## Field Meanings

### LineMetadata Fields

| Field | Type | Meaning | Example |
|-------|------|---------|---------|
| `line_num` | int | Original line number from source file (1-indexed). Set to `-1` for filler lines. | `3` means line 3 from original file |
| `type` | HighlightType | Line-level highlight. `HL_LINE_INSERT` (green) or `HL_LINE_DELETE` (red). | `HL_LINE_DELETE` on left side |
| `is_filler` | bool | Whether this is an empty placeholder line for alignment. | `true` means empty line for sync |
| `char_highlight_count` | int | Number of character-level highlights on this line. | `2` means two character ranges |
| `char_highlights` | Array | Character-level highlights for fine-grained diff. | See CharHighlight below |

### CharHighlight Fields

| Field | Type | Meaning | Example |
|-------|------|---------|---------|
| `start_col` | int | Start column (0-indexed, inclusive). | `5` means 6th character |
| `end_col` | int | End column (0-indexed, exclusive). | `10` means up to (not including) 11th char |
| `type` | HighlightType | Character-level highlight type. | `HL_CHAR_DELETE` for deleted chars |

### HighlightType Values

| Value | Name | Meaning | Visual |
|-------|------|---------|--------|
| 0 | `HL_LINE_INSERT` | Entire line inserted | Light green background |
| 1 | `HL_LINE_DELETE` | Entire line deleted | Light red background |
| 2 | `HL_CHAR_INSERT` | Character(s) inserted | Dark green background |
| 3 | `HL_CHAR_DELETE` | Character(s) deleted | Dark red background |

## VSCode Parity

### VSCode Architecture

VSCode's diff editor uses similar concepts from `DiffEditorWidget.ts`:

**VSCode Source**: [`src/vs/editor/browser/widget/diffEditorWidget.ts`](https://github.com/microsoft/vscode/blob/main/src/vs/editor/browser/widget/diffEditorWidget.ts)

| VSCode Concept | Our Equivalent | Purpose |
|----------------|----------------|---------|
| `LineChange` | `LineMetadata` | Describes change type per line |
| `ViewZone` | `is_filler` flag | Empty lines for alignment |
| `decorations` | `char_highlights` | Character-level styling |
| `originalEditor` | `left` buffer | Original file content |
| `modifiedEditor` | `right` buffer | Modified file content |

**Key Difference**: VSCode uses Myers diff for line-level changes; we use LCS. Both produce minimal diffs but may differ in edge cases. Character-level diff uses Myers algorithm in both.

## Examples

### Example 1: Simple Insertion

**Input**:
```
Left:  ["line 1", "line 3"]
Right: ["line 1", "line 2", "line 3"]
```

**Render Plan**:
```
Left:
  [0] line_num=1, type=OTHER, is_filler=false      → "line 1" (unchanged)
  [1] line_num=-1, type=INSERT, is_filler=true     → (empty line for alignment)
  [2] line_num=2, type=OTHER, is_filler=false      → "line 3" (unchanged)

Right:
  [0] line_num=1, type=OTHER, is_filler=false      → "line 1" (unchanged)
  [1] line_num=2, type=INSERT, is_filler=false     → "line 2" (inserted, green)
  [2] line_num=3, type=OTHER, is_filler=false      → "line 3" (unchanged)
```

### Example 2: Modification with Character Diff

**Input**:
```
Left:  ["hello world"]
Right: ["hello beautiful world"]
```

**Render Plan**:
```
Left:
  [0] line_num=1, type=DELETE, is_filler=false, char_highlights:
      char[6-11] type=CHAR_DELETE                  → "world" deleted

Right:
  [0] line_num=1, type=INSERT, is_filler=false, char_highlights:
      char[6-15] type=CHAR_INSERT                  → "beautiful" inserted
```

**Visual Result**:
```
Left:  hello [world]           (red background on "world")
Right: hello [beautiful ]world (green background on "beautiful ")
```

## Verbose Output Format

When verbose mode is enabled, the render plan is printed in a structured format:

### Output Structure

The C-core produces a **fixed-width 80-character box** with:
- `[C-CORE]` prefix for easy identification
- ANSI color coding when outputting to a TTY:
  - **Cyan**: Headers and labels
  - **Yellow**: Box borders
  - **Green**: INSERT operations
  - **Red**: DELETE operations
  - **Cyan**: Character highlight arrows
- Fallback to plain text when no TTY is available

The Lua layer produces:
- `[LUA]` prefix for easy identification
- Simple text output (no ANSI codes for maximum compatibility)
- Operation summaries (start/end of diff computation)

### Example Output

```
[LUA] Computing diff: 2 lines (left) vs 3 lines (right)

╔══════════════════════════════════════════════════════════════════════════════╗
║ [C-CORE] RENDER PLAN                                                        ║
╚══════════════════════════════════════════════════════════════════════════════╝

┌─ LEFT BUFFER (3 lines) ─────────────────────────────────────────────────────┐
│                                                                              │
│  [0] line_num=1   type=OTHER       filler=NO  char_hl=0                     │
│                                                                              │
│  [1] line_num=0   type=DELETE      filler=YES char_hl=0                     │
│                                                                              │
│  [2] line_num=2   type=INSERT      filler=NO  char_hl=2                     │
│      ↳ char[0-5] type=CHAR_INSERT                                          │
│      ↳ char[10-15] type=CHAR_INSERT                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ RIGHT BUFFER (3 lines) ────────────────────────────────────────────────────┐
│                                                                              │
│  [0] line_num=1   type=OTHER       filler=NO  char_hl=0                     │
│                                                                              │
│  [1] line_num=2   type=INSERT      filler=NO  char_hl=1                     │
│      ↳ char[0-10] type=CHAR_INSERT                                         │
│                                                                              │
│  [2] line_num=3   type=INSERT      filler=NO  char_hl=0                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

[LUA] Render plan created: LEFT=3 lines, RIGHT=3 lines
```

### Field Meanings in Verbose Output

- **Index `[0]`**: Position in the display buffer (0-indexed)
- **line_num**: Original line number (`-1` = filler line)
- **type**: Line highlight type (OTHER, INSERT, DELETE)
- **filler**: Whether this is an alignment line (YES/NO)
- **char_hl**: Count of character-level highlights

Character highlights (if any) are shown indented below the line, indicating exact column ranges and types.

## Implementation Notes

1. **Filler Lines**: Always have `line_num=-1` and `is_filler=true`. They contain no actual content.

2. **Line Numbering**: Uses 1-based indexing to match editor conventions. Index `[0]` in the array corresponds to `line_num=1`.

3. **Column Indexing**: Character highlights use 0-based indexing (standard for string operations).

4. **Memory Management**: C core allocates the render plan; Lua layer must call `free_render_plan()` after use.

5. **Alignment**: Filler lines ensure left and right buffers have equal visual heights for synchronized scrolling.

---

**Last Updated**: 2024-10-23  
**Maintained By**: vscode-diff.nvim project
