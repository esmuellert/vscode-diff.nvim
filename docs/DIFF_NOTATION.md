# Diff Output Notation Reference

## Overview

This document describes the two standard notations used throughout the VSCode diff algorithm implementation for representing differences at different granularities: **line-level diffs** and **character-level mappings**.

---

## Line-Level Diff Notation

### Format

```
seq1[start,end) -> seq2[start,end)
```

### Components

- **seq1**: Original sequence (file)
- **seq2**: Modified sequence (file)
- **[start,end)**: Half-open interval notation
  - `start`: Inclusive starting index (0-based)
  - `end`: Exclusive ending index
  - Range includes indices from `start` to `end-1`

### Interpretation

This notation represents a **line-level difference** between two files. It indicates which lines in the original file differ from which lines in the modified file.

### Examples

#### Example 1: Single Line Change
```
seq1[1,2) -> seq2[1,2)
```
**Meaning:**
- Line at index 1 (second line, 0-based) in the original file
- Differs from line at index 1 in the modified file
- Only one line is affected (2-1 = 1 line)

#### Example 2: Multi-Line Change
```
seq1[0,5) -> seq2[0,7)
```
**Meaning:**
- Lines 0-4 (5 lines) in the original file
- Map to lines 0-6 (7 lines) in the modified file
- Original had 5 lines, modified has 7 lines (2 lines inserted)

#### Example 3: Insertion
```
seq1[1,1) -> seq2[1,3)
```
**Meaning:**
- Empty range `[1,1)` in original (0 lines) = insertion point before index 1
- Maps to `[1,3)` in modified (2 lines) = indices 1 and 2
- **Result:** 2 lines inserted at position 1 (after first line)
- Concrete: If original is `['a', 'b']`, modified is `['a', 'x', 'y', 'b']`

#### Example 4: Deletion
```
seq1[2,5) -> seq2[2,2)
```
**Meaning:**
- Range `[2,5)` in original (3 lines) = indices 2, 3, 4
- Empty range `[2,2)` in modified (0 lines) = deletion occurred
- **Result:** 3 lines deleted starting at position 2

#### Example 5: Multiple Diffs
```
[0] seq1[1,2) -> seq2[1,2)
[1] seq1[4,5) -> seq2[4,5)
```
**Meaning:**
- Two separate diff regions
- Lines 1 and 4 are different
- Lines 2-3 are the same (gap between diffs)

### Half-Open Interval Rationale

The exclusive end index provides several benefits:

1. **Empty ranges**: `[5,5)` represents an empty range (useful for insertions)
   - `[1,1)` means "the position just before index 1"
   - Equivalent to `array.insert(1, item)` in most languages
   - Visual: `['a', 'b', 'c']` → insert at `[1,1)` → `['a', 'x', 'b', 'c']`
   
2. **Length calculation**: `end - start` gives the length directly

3. **Concatenation**: `[0,5)` + `[5,10)` = `[0,10)` with no gap or overlap

4. **Standard practice**: Consistent with array slicing in most programming languages

### Insertion Points

Empty ranges indicate insertion positions:

```
Array indices:  0      1      2
Array values:  'a'    'b'    'c'
Insertion pts:    [0,0) [1,1) [2,2) [3,3)
                    ↓     ↓     ↓      ↓
                 before before before after
                   'a'   'b'   'c'    'c'
```

- `[0,0)` = before index 0 (start of array)
- `[1,1)` = before index 1 (after index 0)
- `[n,n)` = before index n (after index n-1)
- `[length,length)` = after last element (end of array)

---

## Character-Level Mapping Notation

### Format

```
L{line}:C{col}-L{line}:C{col} -> L{line}:C{col}-L{line}:C{col}
```

### Components

- **L**: Line number (1-based for human readability)
- **C**: Column number (1-based for human readability)
- **Range**: `start_line:start_col - end_line:end_col`
  - Start position: `L{line}:C{col}`
  - End position: `L{line}:C{col}` (exclusive, same as line-level)
- **Arrow (->)**: Maps original range to modified range

### Interpretation

This notation represents a **character-level difference** within lines, providing precise positions for inline highlighting. It specifies exactly which characters changed and where.

### Examples

#### Example 1: Single Word Change
```
L1:C7-L1:C12 -> L1:C7-L1:C15
```
**Meaning:**
- **Original**: Line 1, columns 7-11 (5 characters)
- **Modified**: Line 1, columns 7-14 (8 characters)
- A word at position 7 was changed from 5 to 8 characters

**Concrete text:**
```
Original: "hello world"
           123456789...
                 ^^^^^     (columns 7-11: "world")
                 
Modified: "hello universe"
           123456789...
                 ^^^^^^^^  (columns 7-14: "universe")
```

#### Example 2: Multiple Character Changes
```
[0] L1:C7-L1:C9  -> L1:C7-L1:C10
[1] L1:C10-L1:C12 -> L1:C11-L1:C12
```
**Meaning:**
- **Mapping 0**: Original chars at columns 7-8 map to modified chars at columns 7-9
- **Mapping 1**: Original chars at columns 10-11 map to modified char at column 11
- Two distinct character-level changes detected within the same line

**Visual representation:**
```
Original: "The quick brown fox"
           123456789...
                 ^^-^^      (two separate regions)
                 
Modified: "The quick red fox"
           123456789...
                 ^^^-^      (corresponding regions)
```

#### Example 3: Multi-Line Character Range
```
L2:C15-L3:C5 -> L2:C15-L3:C8
```
**Meaning:**
- Change spans multiple lines
- Original: From line 2, column 15 to line 3, column 4
- Modified: From line 2, column 15 to line 3, column 7
- The modified version has 3 more characters in the range

### Column Numbering

Character positions use **1-based indexing** for human readability:

```
Text:     "hello"
Position:  12345
Column:    C1 C2 C3 C4 C5
```

This matches how text editors display cursor positions.

---

## Usage Context

### Line-Level Notation (Steps 1-3)

Used in:
- **Step 1**: Myers algorithm output
- **Step 2**: Optimized sequence diffs
- **Step 3**: After removing short matches

**Purpose**: Identify which lines changed at a high level

**Printed by**: `print_sequence_diff_array()`

### Character-Level Notation (Step 4+)

Used in:
- **Step 4**: Character-level refinement output
- **Step 7**: Render plan generation (for precise highlighting)

**Purpose**: Pinpoint exact character changes for inline diff highlighting

**Printed by**: `print_range_mapping_array()`

---

## Relationship Between Notations

The two notations work together in the diff pipeline:

```
Line-Level (coarse):
  seq1[1,2) -> seq2[1,2)
  "Line 1 changed"

       ↓ Refinement (Step 4)

Character-Level (precise):
  L1:C7-L1:C12 -> L1:C7-L1:C15
  "Characters 7-11 changed to 7-14"
```

**Example transformation:**
```
Input:
  Original line 1: "hello world"
  Modified line 1: "hello there"

Line-level output (Step 1):
  seq1[0,1) -> seq2[0,1)
  
Character-level output (Step 4):
  [0] L1:C7-L1:C9  -> L1:C7-L1:C10
  [1] L1:C10-L1:C12 -> L1:C11-L1:C12
```

The line-level notation tells us **which lines** changed. The character-level notation tells us **exactly where** within those lines.

---

## Rendering Interpretation

### For Highlighting

Character-level mappings are typically merged during rendering (Step 7) for visual clarity:

**Character mappings (raw):**
```
[0] L1:C7-L1:C9
[1] L1:C10-L1:C12
```

**Rendered highlight (merged):**
```
L1:C7-L1:C12  (one continuous highlight block)
```

This prevents "choppy" highlighting where individual characters alternate between highlighted and non-highlighted states.

---

## API Usage

### Printing Functions

```c
#include "print_utils.h"

// Print line-level diffs
SequenceDiffArray* diffs = myers_diff_algorithm(lines_a, len_a, lines_b, len_b);
print_sequence_diff_array("Myers output", diffs);

// Print character-level mappings
RangeMappingArray* refined = refine_diffs_to_char_level(diffs, lines_a, len_a, lines_b, len_b);
print_range_mapping_array("Character mappings", refined);
```

### Output Format

```
Myers output: 2 diff(s)
  [0] seq1[1,2) -> seq2[1,2)
  [1] seq1[4,5) -> seq2[4,5)

Character mappings: 3 character mapping(s)
  [0] L1:C7-L1:C12 -> L1:C7-L1:C15
  [1] L4:C1-L4:C8 -> L4:C1-L4:C10
  [2] L4:C20-L4:C25 -> L4:C22-L4:C28
```

---

## Summary

| Aspect | Line-Level | Character-Level |
|--------|-----------|-----------------|
| **Format** | `seq1[start,end) -> seq2[start,end)` | `L{line}:C{col}-L{line}:C{col} -> ...` |
| **Granularity** | Lines | Characters |
| **Indexing** | 0-based | 1-based (for readability) |
| **Steps** | Steps 1-3 | Step 4+ |
| **Purpose** | Identify changed lines | Precise highlighting |
| **Printer** | `print_sequence_diff_array()` | `print_range_mapping_array()` |

Both notations use **half-open intervals** (exclusive end) for consistency and mathematical elegance. Together, they provide a complete picture of file differences from coarse line-level changes to fine-grained character-level edits.
