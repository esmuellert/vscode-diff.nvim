# Full Parity Finishing Checklist (after char-level timeout fix)

> Goal: once the char-level timeout bubble is wired, finish cloning VS Code’s `DefaultLinesDiffComputer.computeDiff` in `diff_core.c` so the C pipeline delivers end‑to‑end parity. Each section below mirrors a block in the TypeScript source and can be implemented incrementally.

## 1. Top-Level Diff Coordinator
- **Suggested function**: `LinesDiffResult compute_lines_diff(...)`
- **Responsibilities**:
  - Accept raw line buffers and options (`timeout`, `ignoreTrimWhitespace`, `extendToSubwords`, `computeMoves`, etc.).
  - Invoke the existing building blocks: `compute_line_alignments`, char-level refinement, whitespace-only scan, move detection, render plan builder.
  - Return a `LinesDiffResult` struct mirroring VS Code’s `LinesDiff` (detailed mappings, moves, `hit_timeout`, optional render plan).
- **Tip**: centralize resource ownership and timeout aggregation so callers have a single entry point.

## 2. Whitespace-Only Segment Scanner
- **Suggested helper**: `scan_whitespace_only_blocks(...)`
- **Inputs**: original/modified line arrays, `SequenceDiffArray`, options (`consider_whitespace_changes`), timeout handle.
- **Logic**:
  1. Walk equal regions between line diffs.
  2. When the full lines differ (only whitespace), synthesize a one-line `SequenceDiff` and call `refine_diff_char_level`.
  3. Append returned `RangeMapping`s to the global alignment list and merge the timeout flag.
- **Placement**: run before and after each refined diff, replicating VS Code’s `scanForWhitespaceChanges`.

## 3. Range Mapping Consolidation & Detailed Line Mappings
- **Helpers**:
  - `RangeMappingArray consolidate_alignments(...)`
  - `DetailedLineRangeMappingArray build_line_mappings(...)`
- **Purpose**:
  - Mimic `lineRangeMappingFromRangeMappings` to stitch character-level `RangeMapping`s into contiguous groups.
  - Attach metadata (`inner_changes`, line spans) and validate line/column bounds exactly like the TypeScript code.

## 4. Move Detection Pipeline
- **Scope**: port `computeMovedLines` and its supporting utilities.
- **Flow**:
  - Reuse perfect hashes plus `SequenceDiff` utilities to detect moved regions.
  - For each move, invoke `refine_diff_char_level` and convert to `DetailedLineRangeMapping` (matching the TS block at lines 188–214).
  - Integrate the resulting `MovedTextArray` into the overall result.

## 5. Render Plan Builder
- **Objective**: replace the current stub inside `diff_core.c`.
- **Output**: `RenderPlan` containing `LineMetadata` and `CharHighlight` arrays for both sides, with filler lines, move decorations, and highlight merging.
- **Key points**:
  - Derive layout from `DetailedLineRangeMappingArray` plus `RangeMappingArray`.
  - Insert filler rows when insert/delete counts differ, fuse char highlight ranges, label moved text.
  - Provide a corresponding `free_render_plan` to release all nested allocations.

## 6. Wiring & Memory Management
- **Timeout**: propagate every stage’s `hit_timeout` up to the coordinator.
- **Ownership**: add explicit `free_*` helpers for new structs (e.g., `free_detailed_line_range_mapping_array`, `free_lines_diff_result`).
- **Verification**: expand unit tests to cover whitespace-only edits, move detection, and render output consistency.

Delivering these pieces will give the C port the same behaviour as VS Code’s diff computer from input hashing through render-plan emission.
