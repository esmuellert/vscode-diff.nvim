Diff Parity Notes
=================

Context
-------
- Goal: make the bundled C port return the same inner character changes as VS Code for the problematic PowerShell fixtures (`a.ps1`, `b.ps1`) and the simpler playground sample.
- All references below point to the upstream sources in the VS Code repo (current sparse checkout at `/tmp/vscode/src/vs/editor/common/diff/...`).

Key Adjustments
---------------
1. Character slice construction  
   - **C change:** `c-diff-core/src/sequence.c` (`char_sequence_create_from_range`, ~L340-600) and header declaration in `c-diff-core/include/sequence.h`.  
   - **VS Code reference:** `linesSliceCharSequence.ts` constructor.  
   - **What was missing:** the old `char_sequence_create` only worked with whole-line spans and trimmed starts implicitly, so partial line ranges (e.g. insertions that begin mid line) were incorrectly normalised. The new helper reproduces how VS Code slices both buffers based on the exact `RangeMapping`.

2. Range-to-range mapping prior to character diff  
   - **C change:** `c-diff-core/src/char_level.c:87-198` (`line_range_mapping_to_range_mapping2`) and its use at the top of `refine_diff_char_level`.  
   - **VS Code reference:** `rangeMapping.ts` `toRangeMapping2`.  
   - **What was missing:** previously the start/end positions were derived from the coarse `SequenceDiff` line indices, ignoring the edge cases handled by VS Code (line starts/ends that fall outside real content). Implementing the same normalisation fixed the misaligned base lines that merged multiple insertions.

3. Feeding refineDiff with position-aware character sequences  
   - **C change:** `refine_diff_char_level` now calls `char_sequence_create_from_range` using the `RangeMapping` produced above.  
   - **VS Code reference:** `defaultLinesDiffComputer.ts` `refineDiff` (the `LinesSliceCharSequence` instances built from `rangeMapping.originalRange/modRange`).  
   - **What was missing:** the previous C version still passed raw line indexes into `char_sequence_create`, so the subsequent character diff observed different offsets than VS Code.

4. Short text heuristic parity  
   - **C change:** `remove_very_short_text` in `c-diff-core/src/char_level.c` now mirrors the “trimmed length ≤ 3 characters” logic by testing `(text_len > 0 && trimmed_len <= 3)` instead of requiring trimmed text to be non-empty.  
   - **VS Code reference:** `heuristicSequenceOptimizations.ts` `removeVeryShortMatchingTextBetweenLongDiffs` (`shouldMarkAsChanged`).  
   - **What was missing:** the previous implementation discarded gaps filled with whitespace only, preventing the big Windows Admin Center chunk from being merged like VS Code.

5. CLI options alignment  
   - **C change:** `c-diff-core/diff_tool.c` now leaves carriage returns intact on read and defaults `extend_to_subwords` to `false`.  
   - **VS Code reference:** wrapper script `vscode-diff.mjs` calling `DefaultLinesDiffComputer` with TS defaults.  
   - **What was missing:** the tool silently stripped `\r` characters and forced `extendToSubwords`, both of which produced different inner-change layouts on CRLF content.

Testing & Validation
--------------------
- `make test-char-level` (Step 4 unit coverage).  
- Manual parity checks:  
  - `c-diff-core/build/diff ../test_playground.txt ../modified_playground.txt`  
  - `node vscode-diff.mjs ../test_playground.txt ../modified_playground.txt`  
  - `c-diff-core/build/diff ../a.ps1 ../b.ps1`  
  - `node vscode-diff.mjs ../a.ps1 ../b.ps1`
  All four produce identical counts and inner segments after the changes above.

