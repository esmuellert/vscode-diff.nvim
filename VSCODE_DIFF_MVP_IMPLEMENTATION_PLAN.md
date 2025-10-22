# VSCode-Style Diff Rendering for Neovim - MVP Implementation Plan

**Generated:** 2025-10-22T06:19:27.645Z  
**Updated:** 2025-10-22T06:51:00.000Z - **Character-level LCS now MANDATORY for MVP**

---

## ⚠️ CRITICAL UPDATE

**Character-level highlighting is NOW a core MVP requirement, NOT optional.**

Without the two-tier highlighting system (light backgrounds + deep character highlights), this plugin is just a re-implementation of Neovim's built-in `diffthis` with no unique value.

**The "deeper color" effect is THE defining feature that makes VSCode's diff superior.**

---

## 🎯 Project Goal

Build an MVP Neovim plugin that mimics VSCode's inline diff rendering by:
1. Computing diff and render plan in **C** (for performance)
2. Passing the render plan to **Lua**
3. Using Lua to apply highlights, filler lines, and virtual text via Neovim APIs

**Stage 1 Scope:** Static diff rendering with read-only buffers (no live updates).

---

## 📁 Project Structure

```
nvim-vscode-diff/
├── README.md                      # Installation & usage instructions
├── Makefile                       # Build automation for C module
├── plugin/
│   └── vscode-diff.lua           # Lazy.nvim entry point
├── lua/
│   └── vscode-diff/
│       ├── init.lua              # Main Lua interface
│       ├── render.lua            # Buffer rendering logic
│       └── config.lua            # Plugin configuration
├── c-diff-core/
│   ├── diff_core.c               # C implementation (diff + render plan)
│   ├── diff_core.h               # C header file
│   └── test_diff_core.c          # C unit tests
└── tests/
    ├── test_render.lua           # Lua rendering tests
    └── fixtures/
        ├── file_a.txt            # Test input file A
        └── file_b.txt            # Test input file B
```

---

## 🔗 VSCode Architecture Reference

Our implementation mimics VSCode's diff rendering architecture:

| **Our Component**          | **VSCode Counterpart**                                                                                     |
|----------------------------|------------------------------------------------------------------------------------------------------------|
| `c-diff-core/diff_core.c`  | `src/vs/editor/common/diff/algorithms/diffAlgorithm.ts`<br>`src/vs/editor/common/diff/standardLinesDiffComputer.ts` |
| `lua/vscode-diff/render.lua` | `src/vs/editor/browser/widget/diffEditorWidget.ts`<br>`src/vs/editor/browser/widget/diffEditorDecorations.ts` |
| Render Plan Data Structure | `src/vs/editor/common/diff/linesDiffComputer.ts` (ILinesDiff interface)                                    |
| Highlight Groups           | `src/vs/editor/common/diff/linesDiffComputer.ts` (character-level changes)                                 |
| Filler Lines (Virtual Text) | `src/vs/editor/browser/widget/diffEditorWidget.ts` (line alignment logic)                                  |

**VSCode Repo:** https://github.com/microsoft/vscode

---

## 📋 Implementation Steps

### **Step 1: Project Setup & C Module Scaffold**

**Objective:** Create project structure and verify C compilation works.

**Tasks:**
1. Create directory structure as shown above
2. Create `Makefile` for building C module
3. Create minimal `diff_core.c` with a test function
4. Verify C compilation produces a shared library

**Files to Create:**

**`Makefile`:**
```makefile
# Detect OS
UNAME_S := $(shell uname -s)

# Compiler settings
CC = gcc
CFLAGS = -Wall -Wextra -O2 -fPIC -std=c11
LDFLAGS = -shared

# Output
ifeq ($(UNAME_S),Linux)
    TARGET = libdiff_core.so
else ifeq ($(UNAME_S),Darwin)
    TARGET = libdiff_core.dylib
else
    TARGET = diff_core.dll
endif

# Source files
SRC = c-diff-core/diff_core.c
OBJ = $(SRC:.c=.o)

# Build targets
all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

test: c-diff-core/test_diff_core.c c-diff-core/diff_core.c
	$(CC) $(CFLAGS) -o test_diff_core $^
	./test_diff_core

clean:
	rm -f $(OBJ) $(TARGET) test_diff_core

.PHONY: all test clean
```

**`c-diff-core/diff_core.h`:**
```c
#ifndef DIFF_CORE_H
#define DIFF_CORE_H

#include <stddef.h>
#include <stdint.h>

// Version info
#define DIFF_CORE_VERSION "0.1.0"

// Test function for Step 1
const char* diff_core_get_version(void);

#endif // DIFF_CORE_H
```

**`c-diff-core/diff_core.c`:**
```c
#include "diff_core.h"

const char* diff_core_get_version(void) {
    return DIFF_CORE_VERSION;
}
```

**`c-diff-core/test_diff_core.c`:**
```c
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "diff_core.h"

void test_version(void) {
    const char* version = diff_core_get_version();
    assert(strcmp(version, "0.1.0") == 0);
    printf("✓ Version test passed: %s\n", version);
}

int main(void) {
    printf("Running C unit tests...\n");
    test_version();
    printf("All tests passed!\n");
    return 0;
}
```

**Validation:**
```bash
# Build C module
make clean && make

# Run C tests
make test

# Expected output:
# Running C unit tests...
# ✓ Version test passed: 0.1.0
# All tests passed!
```

**VSCode Reference:** Similar to VSCode's C++ extension modules build setup.

---

### **Step 2: Define Render Plan Data Structure**

**Objective:** Define the C data structure that represents the diff render plan.

**VSCode Reference:** 
- `src/vs/editor/common/diff/linesDiffComputer.ts` (ILinesDiff interface)
- `src/vs/editor/common/diff/rangeMapping.ts`

**Tasks:**
1. Define C structs for render plan
2. Implement memory management functions
3. Add unit tests for data structure creation/destruction

**Update `c-diff-core/diff_core.h`:**
```c
#ifndef DIFF_CORE_H
#define DIFF_CORE_H

#include <stddef.h>
#include <stdint.h>

// Version info
#define DIFF_CORE_VERSION "0.1.0"

// ============================================================================
// Data Structures (mimics VSCode's ILinesDiff and character-level changes)
// ============================================================================

// Highlight type for a character range
typedef enum {
    HL_ADDED,      // Green background (added text)
    HL_REMOVED,    // Red background (removed text)
    HL_MODIFIED    // Blue/darker shade (modified within line)
} HighlightType;

// A single character-level highlight
typedef struct {
    size_t line;           // 0-based line number in buffer
    size_t col_start;      // 0-based column start (byte index)
    size_t col_end;        // 0-based column end (byte index)
    HighlightType type;    // Highlight type
} CharHighlight;

// Filler line (for alignment)
typedef struct {
    size_t line_after;     // Insert filler after this line (0-based)
    size_t count;          // Number of filler lines to insert
} FillerLine;

// Line change type (for full-line background)
typedef enum {
    LINE_ADDED,
    LINE_REMOVED,
    LINE_MODIFIED,
    LINE_UNCHANGED
} LineChangeType;

// Full line metadata
typedef struct {
    size_t line;           // 0-based line number
    LineChangeType type;   // Change type
} LineMetadata;

// The complete render plan for one buffer (left or right)
typedef struct {
    // Character-level highlights
    CharHighlight* char_highlights;
    size_t char_highlights_count;
    
    // Filler lines (for alignment)
    FillerLine* filler_lines;
    size_t filler_lines_count;
    
    // Line metadata (for full-line backgrounds)
    LineMetadata* line_metadata;
    size_t line_metadata_count;
} BufferRenderPlan;

// Complete diff render plan (both buffers)
typedef struct {
    BufferRenderPlan left;   // Render plan for left buffer
    BufferRenderPlan right;  // Render plan for right buffer
} DiffRenderPlan;

// ============================================================================
// API Functions
// ============================================================================

// Get version
const char* diff_core_get_version(void);

// Create empty render plan
DiffRenderPlan* diff_render_plan_create(void);

// Free render plan
void diff_render_plan_free(DiffRenderPlan* plan);

#endif // DIFF_CORE_H
```

**Update `c-diff-core/diff_core.c`:**
```c
#include "diff_core.h"
#include <stdlib.h>
#include <string.h>

const char* diff_core_get_version(void) {
    return DIFF_CORE_VERSION;
}

DiffRenderPlan* diff_render_plan_create(void) {
    DiffRenderPlan* plan = (DiffRenderPlan*)calloc(1, sizeof(DiffRenderPlan));
    if (!plan) return NULL;
    
    memset(plan, 0, sizeof(DiffRenderPlan));
    return plan;
}

void diff_render_plan_free(DiffRenderPlan* plan) {
    if (!plan) return;
    
    // Free left buffer data
    free(plan->left.char_highlights);
    free(plan->left.filler_lines);
    free(plan->left.line_metadata);
    
    // Free right buffer data
    free(plan->right.char_highlights);
    free(plan->right.filler_lines);
    free(plan->right.line_metadata);
    
    // Free the plan itself
    free(plan);
}
```

**Update `c-diff-core/test_diff_core.c`:**
```c
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "diff_core.h"

void test_version(void) {
    const char* version = diff_core_get_version();
    assert(strcmp(version, "0.1.0") == 0);
    printf("✓ Version test passed: %s\n", version);
}

void test_render_plan_lifecycle(void) {
    DiffRenderPlan* plan = diff_render_plan_create();
    assert(plan != NULL);
    assert(plan->left.char_highlights_count == 0);
    assert(plan->right.char_highlights_count == 0);
    
    diff_render_plan_free(plan);
    printf("✓ Render plan lifecycle test passed\n");
}

int main(void) {
    printf("Running C unit tests...\n");
    test_version();
    test_render_plan_lifecycle();
    printf("All tests passed!\n");
    return 0;
}
```

**Validation:**
```bash
make test

# Expected output:
# Running C unit tests...
# ✓ Version test passed: 0.1.0
# ✓ Render plan lifecycle test passed
# All tests passed!
```

**VSCode Reference:** Matches the data structure patterns in `src/vs/editor/common/diff/linesDiffComputer.ts`.

---

### **Step 3: Implement Myers Diff Algorithm**

**Objective:** Implement line-level diff using Myers algorithm.

**VSCode Reference:** 
- `src/vs/editor/common/diff/algorithms/myersDiffAlgorithm.ts`
- `src/vs/base/common/diff/diff.ts`

**Tasks:**
1. Implement Myers diff for line-level changes
2. Generate line change types (ADDED, REMOVED, MODIFIED, UNCHANGED)
3. Add unit tests with simple file fixtures

**Update `c-diff-core/diff_core.h`:**
```c
// Add this function declaration:

// Compute diff between two files and generate render plan
// Returns NULL on error
DiffRenderPlan* diff_compute(const char** lines_a, size_t lines_a_count,
                              const char** lines_b, size_t lines_b_count);
```

**Update `c-diff-core/diff_core.c`:**
```c
// Add Myers diff implementation (simplified version)
// Full implementation would be ~200-300 lines
// For now, create a stub that handles simple cases

#include <string.h>

// Helper: compare two lines
static int lines_equal(const char* a, const char* b) {
    return strcmp(a, b) == 0;
}

DiffRenderPlan* diff_compute(const char** lines_a, size_t lines_a_count,
                              const char** lines_b, size_t lines_b_count) {
    DiffRenderPlan* plan = diff_render_plan_create();
    if (!plan) return NULL;
    
    // Allocate line metadata for both buffers
    plan->left.line_metadata = (LineMetadata*)calloc(lines_a_count, sizeof(LineMetadata));
    plan->left.line_metadata_count = lines_a_count;
    
    plan->right.line_metadata = (LineMetadata*)calloc(lines_b_count, sizeof(LineMetadata));
    plan->right.line_metadata_count = lines_b_count;
    
    // Simple diff: compare line by line (naive implementation)
    // Real implementation would use Myers algorithm
    size_t i = 0, j = 0;
    while (i < lines_a_count && j < lines_b_count) {
        if (lines_equal(lines_a[i], lines_b[j])) {
            // Lines match - UNCHANGED
            plan->left.line_metadata[i].line = i;
            plan->left.line_metadata[i].type = LINE_UNCHANGED;
            plan->right.line_metadata[j].line = j;
            plan->right.line_metadata[j].type = LINE_UNCHANGED;
            i++;
            j++;
        } else {
            // Lines differ - mark as MODIFIED for now
            plan->left.line_metadata[i].line = i;
            plan->left.line_metadata[i].type = LINE_MODIFIED;
            plan->right.line_metadata[j].line = j;
            plan->right.line_metadata[j].type = LINE_MODIFIED;
            i++;
            j++;
        }
    }
    
    // Handle remaining lines
    while (i < lines_a_count) {
        plan->left.line_metadata[i].line = i;
        plan->left.line_metadata[i].type = LINE_REMOVED;
        i++;
    }
    
    while (j < lines_b_count) {
        plan->right.line_metadata[j].line = j;
        plan->right.line_metadata[j].type = LINE_ADDED;
        j++;
    }
    
    return plan;
}
```

**Create Test Fixtures:**

**`tests/fixtures/file_a.txt`:**
```
function hello() {
  console.log("Hello");
  return 42;
}
```

**`tests/fixtures/file_b.txt`:**
```
function hello() {
  console.log("Hello, World!");
  return 42;
}
```

**Update `c-diff-core/test_diff_core.c`:**
```c
void test_simple_diff(void) {
    const char* lines_a[] = {
        "function hello() {",
        "  console.log(\"Hello\");",
        "  return 42;",
        "}"
    };
    
    const char* lines_b[] = {
        "function hello() {",
        "  console.log(\"Hello, World!\");",
        "  return 42;",
        "}"
    };
    
    DiffRenderPlan* plan = diff_compute(lines_a, 4, lines_b, 4);
    assert(plan != NULL);
    
    // Line 0: UNCHANGED
    assert(plan->left.line_metadata[0].type == LINE_UNCHANGED);
    assert(plan->right.line_metadata[0].type == LINE_UNCHANGED);
    
    // Line 1: MODIFIED
    assert(plan->left.line_metadata[1].type == LINE_MODIFIED);
    assert(plan->right.line_metadata[1].type == LINE_MODIFIED);
    
    // Line 2-3: UNCHANGED
    assert(plan->left.line_metadata[2].type == LINE_UNCHANGED);
    assert(plan->right.line_metadata[2].type == LINE_UNCHANGED);
    
    diff_render_plan_free(plan);
    printf("✓ Simple diff test passed\n");
}

int main(void) {
    printf("Running C unit tests...\n");
    test_version();
    test_render_plan_lifecycle();
    test_simple_diff();
    printf("All tests passed!\n");
    return 0;
}
```

**Validation:**
```bash
make test

# Expected output:
# Running C unit tests...
# ✓ Version test passed: 0.1.0
# ✓ Render plan lifecycle test passed
# ✓ Simple diff test passed
# All tests passed!
```

**Note for Code Agent:** The above is a **simplified stub**. For production, implement full Myers algorithm following VSCode's `myersDiffAlgorithm.ts` logic. The stub is sufficient for initial testing only.

---

### **Step 4: Implement Character-Level Diff (CRITICAL FOR MVP)**

**Objective:** For MODIFIED lines, compute character-level changes using LCS.

**⚠️ IMPORTANCE:** This is **THE defining feature** that makes this plugin different from `diffthis`. Without it, the MVP has no unique value. This is **NOT optional**.

**VSCode Reference:**
- `src/vs/editor/common/diff/algorithms/diffAlgorithm.ts` (character diff)
- `src/vs/editor/common/diff/linesDiffComputer.ts` (computeCharChanges)
- VSCode uses a two-tier highlighting system:
  - **Light background**: Entire modified line (red/green)
  - **Dark/deep highlight**: Only the changed characters within that line

**Tasks:**
1. Implement character-level LCS algorithm for modified lines
2. Generate **two types** of highlights per modified line:
   - Whole-line background (light red/green)
   - Character-range highlights (dark red/green) for changed portions
3. Add comprehensive tests

**Algorithm Overview:**

For two modified lines:
```
Old: "const oldValue = 42;"
New: "const newValue = 42;"
```

1. **LCS (Longest Common Subsequence)** finds common parts: `"const "`, `"Value = 42;"`
2. **Diff parts**: `"old"` vs `"new"`
3. **Generate highlights**:
   - Left line: Light red background (full line) + Dark red for `"old"` (chars 6-9)
   - Right line: Light green background (full line) + Dark green for `"new"` (chars 6-9)

**Update `c-diff-core/diff_core.h`:**
```c
// Update HighlightType enum to support two-tier highlighting
typedef enum {
    HL_ADDED_LINE,      // Light green background (full line)
    HL_REMOVED_LINE,    // Light red background (full line)
    HL_ADDED_CHAR,      // Dark green (changed characters only)
    HL_REMOVED_CHAR,    // Dark red (changed characters only)
    HL_MODIFIED_LINE    // Light blue background (full line)
} HighlightType;
```

**Update `c-diff-core/diff_core.c`:**
```c
#include <string.h>
#include <stdlib.h>

// LCS-based character diff implementation
// This is the CRITICAL function that makes us different from diffthis

typedef struct {
    size_t start;
    size_t end;
} CharRange;

// Helper: Compute LCS length table (dynamic programming)
static size_t** compute_lcs_table(const char* a, size_t len_a, 
                                   const char* b, size_t len_b) {
    size_t** lcs = (size_t**)malloc((len_a + 1) * sizeof(size_t*));
    
    for (size_t i = 0; i <= len_a; i++) {
        lcs[i] = (size_t*)calloc(len_b + 1, sizeof(size_t));
    }
    
    // Fill LCS table
    for (size_t i = 1; i <= len_a; i++) {
        for (size_t j = 1; j <= len_b; j++) {
            if (a[i-1] == b[j-1]) {
                lcs[i][j] = lcs[i-1][j-1] + 1;
            } else {
                lcs[i][j] = (lcs[i-1][j] > lcs[i][j-1]) ? lcs[i-1][j] : lcs[i][j-1];
            }
        }
    }
    
    return lcs;
}

// Helper: Free LCS table
static void free_lcs_table(size_t** lcs, size_t len_a) {
    for (size_t i = 0; i <= len_a; i++) {
        free(lcs[i]);
    }
    free(lcs);
}

// Helper: Extract changed character ranges using LCS backtracking
static void extract_char_ranges(const char* a, size_t len_a,
                                 const char* b, size_t len_b,
                                 size_t** lcs,
                                 CharRange** ranges_a, size_t* ranges_a_count,
                                 CharRange** ranges_b, size_t* ranges_b_count) {
    // Backtrack through LCS table to find differences
    size_t i = len_a, j = len_b;
    size_t ranges_capacity = 16;
    
    *ranges_a = (CharRange*)malloc(ranges_capacity * sizeof(CharRange));
    *ranges_b = (CharRange*)malloc(ranges_capacity * sizeof(CharRange));
    *ranges_a_count = 0;
    *ranges_b_count = 0;
    
    size_t range_start_a = len_a, range_start_b = len_b;
    
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && a[i-1] == b[j-1]) {
            // Characters match - if we were in a diff range, close it
            if (range_start_a < i) {
                // Add range to left (deleted chars)
                if (*ranges_a_count >= ranges_capacity) {
                    ranges_capacity *= 2;
                    *ranges_a = (CharRange*)realloc(*ranges_a, ranges_capacity * sizeof(CharRange));
                }
                (*ranges_a)[*ranges_a_count].start = range_start_a;
                (*ranges_a)[*ranges_a_count].end = i;
                (*ranges_a_count)++;
                range_start_a = len_a;
            }
            if (range_start_b < j) {
                // Add range to right (added chars)
                if (*ranges_b_count >= ranges_capacity) {
                    ranges_capacity *= 2;
                    *ranges_b = (CharRange*)realloc(*ranges_b, ranges_capacity * sizeof(CharRange));
                }
                (*ranges_b)[*ranges_b_count].start = range_start_b;
                (*ranges_b)[*ranges_b_count].end = j;
                (*ranges_b_count)++;
                range_start_b = len_b;
            }
            i--;
            j--;
        } else if (j > 0 && (i == 0 || lcs[i][j-1] >= lcs[i-1][j])) {
            // Character added in b
            if (range_start_b == len_b) {
                range_start_b = j - 1;
            }
            j--;
        } else if (i > 0) {
            // Character deleted in a
            if (range_start_a == len_a) {
                range_start_a = i - 1;
            }
            i--;
        }
    }
    
    // Close any remaining ranges
    if (range_start_a < len_a) {
        (*ranges_a)[*ranges_a_count].start = 0;
        (*ranges_a)[*ranges_a_count].end = range_start_a + 1;
        (*ranges_a_count)++;
    }
    if (range_start_b < len_b) {
        (*ranges_b)[*ranges_b_count].start = 0;
        (*ranges_b)[*ranges_b_count].end = range_start_b + 1;
        (*ranges_b_count)++;
    }
}

// Main character-level diff function
static void compute_char_diff(const char* line_a, const char* line_b,
                               size_t line_num_a, size_t line_num_b,
                               DiffRenderPlan* plan) {
    size_t len_a = strlen(line_a);
    size_t len_b = strlen(line_b);
    
    // Step 1: Add whole-line background highlights
    // Left line: light red background
    plan->left.char_highlights = (CharHighlight*)realloc(
        plan->left.char_highlights,
        (plan->left.char_highlights_count + 1) * sizeof(CharHighlight)
    );
    CharHighlight line_hl_left = {
        .line = line_num_a,
        .col_start = 0,
        .col_end = len_a,
        .type = HL_REMOVED_LINE  // Light red
    };
    plan->left.char_highlights[plan->left.char_highlights_count++] = line_hl_left;
    
    // Right line: light green background
    plan->right.char_highlights = (CharHighlight*)realloc(
        plan->right.char_highlights,
        (plan->right.char_highlights_count + 1) * sizeof(CharHighlight)
    );
    CharHighlight line_hl_right = {
        .line = line_num_b,
        .col_start = 0,
        .col_end = len_b,
        .type = HL_ADDED_LINE  // Light green
    };
    plan->right.char_highlights[plan->right.char_highlights_count++] = line_hl_right;
    
    // Step 2: Compute LCS and find changed character ranges
    size_t** lcs = compute_lcs_table(line_a, len_a, line_b, len_b);
    
    CharRange* ranges_a = NULL;
    CharRange* ranges_b = NULL;
    size_t ranges_a_count = 0;
    size_t ranges_b_count = 0;
    
    extract_char_ranges(line_a, len_a, line_b, len_b, lcs,
                        &ranges_a, &ranges_a_count,
                        &ranges_b, &ranges_b_count);
    
    // Step 3: Add deep highlights for changed characters only
    // Left: dark red for deleted chars
    for (size_t i = 0; i < ranges_a_count; i++) {
        plan->left.char_highlights = (CharHighlight*)realloc(
            plan->left.char_highlights,
            (plan->left.char_highlights_count + 1) * sizeof(CharHighlight)
        );
        CharHighlight char_hl = {
            .line = line_num_a,
            .col_start = ranges_a[i].start,
            .col_end = ranges_a[i].end,
            .type = HL_REMOVED_CHAR  // Dark red (the "deeper color"!)
        };
        plan->left.char_highlights[plan->left.char_highlights_count++] = char_hl;
    }
    
    // Right: dark green for added chars
    for (size_t i = 0; i < ranges_b_count; i++) {
        plan->right.char_highlights = (CharHighlight*)realloc(
            plan->right.char_highlights,
            (plan->right.char_highlights_count + 1) * sizeof(CharHighlight)
        );
        CharHighlight char_hl = {
            .line = line_num_b,
            .col_start = ranges_b[i].start,
            .col_end = ranges_b[i].end,
            .type = HL_ADDED_CHAR  // Dark green (the "deeper color"!)
        };
        plan->right.char_highlights[plan->right.char_highlights_count++] = char_hl;
    }
    
    // Cleanup
    free_lcs_table(lcs, len_a);
    free(ranges_a);
    free(ranges_b);
}

// Update diff_compute to call compute_char_diff for MODIFIED lines
// In the main diff loop, whenever you detect LINE_MODIFIED, call:
// compute_char_diff(lines_a[i], lines_b[j], i, j, plan);
```

**Update `c-diff-core/test_diff_core.c`:**
```c
void test_char_level_diff(void) {
    const char* line_a = "const oldValue = 42;";
    const char* line_b = "const newValue = 42;";
    
    DiffRenderPlan* plan = diff_render_plan_create();
    
    // Manually call char diff (in real code, this is called from diff_compute)
    compute_char_diff(line_a, line_b, 0, 0, plan);
    
    // Should have highlights for both lines
    assert(plan->left.char_highlights_count >= 2);  // At least: line bg + char range
    assert(plan->right.char_highlights_count >= 2); // At least: line bg + char range
    
    // Find the character-level highlights (not the line backgrounds)
    int found_left_char = 0, found_right_char = 0;
    for (size_t i = 0; i < plan->left.char_highlights_count; i++) {
        if (plan->left.char_highlights[i].type == HL_REMOVED_CHAR) {
            // Should highlight "old" (roughly chars 6-9)
            assert(plan->left.char_highlights[i].col_start >= 5);
            assert(plan->left.char_highlights[i].col_end <= 10);
            found_left_char = 1;
        }
    }
    
    for (size_t i = 0; i < plan->right.char_highlights_count; i++) {
        if (plan->right.char_highlights[i].type == HL_ADDED_CHAR) {
            // Should highlight "new" (roughly chars 6-9)
            assert(plan->right.char_highlights[i].col_start >= 5);
            assert(plan->right.char_highlights[i].col_end <= 10);
            found_right_char = 1;
        }
    }
    
    assert(found_left_char == 1);
    assert(found_right_char == 1);
    
    diff_render_plan_free(plan);
    printf("✓ Character-level diff test passed (LCS working!)\n");
}
```

**Validation:** 
```bash
make test

# Expected output:
# Running C unit tests...
# ✓ Version test passed: 0.1.0
# ✓ Render plan lifecycle test passed
# ✓ Simple diff test passed
# ✓ Character-level diff test passed (LCS working!)
# All tests passed!
```

**Visual Result:**

When viewing a modified line like:
```
Old: "const oldValue = 42;"
New: "const newValue = 42;"
```

You will see:
- **Left buffer**: Light red background on entire line + **Dark red** on "old" only
- **Right buffer**: Light green background on entire line + **Dark green** on "new" only

**This is the "deeper color" you noticed in VSCode!** 🎯

---

### **Step 5: Implement Line Alignment (Filler Lines)**

**Objective:** Compute where to insert filler lines for proper alignment.

**VSCode Reference:**
- `src/vs/editor/browser/widget/diffEditorWidget.ts` (line alignment logic)

**Tasks:**
1. Compute filler line positions based on diff
2. Populate FillerLine arrays in render plan
3. Add tests

**Logic:**
- If left has line removed, insert filler in right at that position
- If right has line added, insert filler in left at that position
- This keeps line numbers aligned

**Update `c-diff-core/diff_core.c`:**
```c
// Add logic to populate filler_lines in diff_compute
// Example: if line 5 is REMOVED on left, add filler to right after line 4
```

**Validation:** Test that filler lines are correctly calculated.

---

### **Step 6: Lua FFI Interface**

**Objective:** Create Lua wrapper to call C functions via FFI.

**Tasks:**
1. Load shared library in Lua
2. Define FFI bindings
3. Call C functions and retrieve render plan

**Create `lua/vscode-diff/init.lua`:**
```lua
local ffi = require("ffi")
local M = {}

-- Load shared library
local lib_path
if jit.os == "Windows" then
  lib_path = "diff_core.dll"
elseif jit.os == "OSX" then
  lib_path = "./libdiff_core.dylib"
else
  lib_path = "./libdiff_core.so"
end

local diff_core = ffi.load(lib_path)

-- Define C API
ffi.cdef[[
  typedef enum {
    HL_ADDED_LINE,      // Light green background (full line)
    HL_REMOVED_LINE,    // Light red background (full line)
    HL_ADDED_CHAR,      // Dark green (changed characters only) ← THE "DEEPER COLOR"!
    HL_REMOVED_CHAR,    // Dark red (changed characters only) ← THE "DEEPER COLOR"!
    HL_MODIFIED_LINE    // Light blue background (full line)
  } HighlightType;

  typedef struct {
    size_t line;
    size_t col_start;
    size_t col_end;
    HighlightType type;
  } CharHighlight;

  typedef struct {
    size_t line_after;
    size_t count;
  } FillerLine;

  typedef enum {
    LINE_ADDED,
    LINE_REMOVED,
    LINE_MODIFIED,
    LINE_UNCHANGED
  } LineChangeType;

  typedef struct {
    size_t line;
    LineChangeType type;
  } LineMetadata;

  typedef struct {
    CharHighlight* char_highlights;
    size_t char_highlights_count;
    FillerLine* filler_lines;
    size_t filler_lines_count;
    LineMetadata* line_metadata;
    size_t line_metadata_count;
  } BufferRenderPlan;

  typedef struct {
    BufferRenderPlan left;
    BufferRenderPlan right;
  } DiffRenderPlan;

  const char* diff_core_get_version(void);
  DiffRenderPlan* diff_compute(const char** lines_a, size_t lines_a_count,
                                const char** lines_b, size_t lines_b_count);
  void diff_render_plan_free(DiffRenderPlan* plan);
]]

-- Lua wrapper function
function M.compute_diff(lines_a, lines_b)
  -- Convert Lua tables to C arrays
  local lines_a_arr = ffi.new("const char*[?]", #lines_a)
  local lines_b_arr = ffi.new("const char*[?]", #lines_b)
  
  for i, line in ipairs(lines_a) do
    lines_a_arr[i - 1] = line
  end
  
  for i, line in ipairs(lines_b) do
    lines_b_arr[i - 1] = line
  end
  
  -- Call C function
  local plan = diff_core.diff_compute(lines_a_arr, #lines_a, lines_b_arr, #lines_b)
  
  if plan == nil then
    error("Failed to compute diff")
  end
  
  -- Convert C structs to Lua tables
  local result = {
    left = {
      char_highlights = {},
      filler_lines = {},
      line_metadata = {}
    },
    right = {
      char_highlights = {},
      filler_lines = {},
      line_metadata = {}
    }
  }
  
  -- Parse left buffer
  for i = 0, tonumber(plan.left.char_highlights_count) - 1 do
    local hl = plan.left.char_highlights[i]
    table.insert(result.left.char_highlights, {
      line = tonumber(hl.line),
      col_start = tonumber(hl.col_start),
      col_end = tonumber(hl.col_end),
      type = tonumber(hl.type)
    })
  end
  
  -- Parse line metadata
  for i = 0, tonumber(plan.left.line_metadata_count) - 1 do
    local meta = plan.left.line_metadata[i]
    table.insert(result.left.line_metadata, {
      line = tonumber(meta.line),
      type = tonumber(meta.type)
    })
  end
  
  -- Same for right buffer...
  -- (Similar parsing code)
  
  -- Free C memory
  diff_core.diff_render_plan_free(plan)
  
  return result
end

function M.get_version()
  return ffi.string(diff_core.diff_core_get_version())
end

return M
```

**Create `tests/test_render.lua`:**
```lua
local diff = require("vscode-diff")

print("Testing Lua FFI...")
print("Version: " .. diff.get_version())

local lines_a = {
  "function hello() {",
  "  console.log(\"Hello\");",
  "  return 42;",
  "}"
}

local lines_b = {
  "function hello() {",
  "  console.log(\"Hello, World!\");",
  "  return 42;",
  "}"
}

local result = diff.compute_diff(lines_a, lines_b)
print("Left line metadata count: " .. #result.left.line_metadata)
print("Right line metadata count: " .. #result.right.line_metadata)
print("✓ Lua FFI test passed")
```

**Validation:**
```bash
# Build C module
make clean && make

# Run Lua test (using nvim headless)
nvim --headless -c "luafile tests/test_render.lua" -c "quit"

# Expected output:
# Testing Lua FFI...
# Version: 0.1.0
# Left line metadata count: 4
# Right line metadata count: 4
# ✓ Lua FFI test passed
```

---

### **Step 7: Buffer Rendering Implementation**

**Objective:** Implement Lua logic to apply render plan to Neovim buffers.

**VSCode Reference:**
- `src/vs/editor/browser/widget/diffEditorDecorations.ts`

**Tasks:**
1. Create/configure two side-by-side buffers
2. Apply highlights using `nvim_buf_add_highlight`
3. Insert filler lines using virtual text (`nvim_buf_set_extmark`)
4. Set buffers to read-only

**Create `lua/vscode-diff/render.lua`:**
```lua
local M = {}

-- Highlight group definitions (VSCode colors)
-- Two-tier system: light backgrounds for lines, dark/deep for changed characters
local function setup_highlight_groups()
  -- Line-level backgrounds (light colors)
  vim.api.nvim_set_hl(0, "DiffAddedLine", { bg = "#1e3a20" })      -- Light green (entire line)
  vim.api.nvim_set_hl(0, "DiffRemovedLine", { bg = "#3a1e1e" })    -- Light red (entire line)
  vim.api.nvim_set_hl(0, "DiffModifiedLine", { bg = "#1e2a3a" })   -- Light blue (entire line)
  
  -- Character-level highlights (dark/deep colors - the "deeper color" you noticed!)
  vim.api.nvim_set_hl(0, "DiffAddedChar", { bg = "#2ea043", fg = "#ffffff" })    -- DEEP GREEN (changed chars only)
  vim.api.nvim_set_hl(0, "DiffRemovedChar", { bg = "#f85149", fg = "#ffffff" })  -- DEEP RED (changed chars only)
end

-- Apply render plan to a buffer
function M.apply_render_plan(bufnr, render_plan)
  local ns = vim.api.nvim_create_namespace("vscode_diff")
  
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  
  -- Apply line-level backgrounds
  for _, meta in ipairs(render_plan.line_metadata) do
    local hl_group
    if meta.type == 0 then -- LINE_ADDED
      hl_group = "DiffAddedLine"
    elseif meta.type == 1 then -- LINE_REMOVED
      hl_group = "DiffRemovedLine"
    elseif meta.type == 2 then -- LINE_MODIFIED
      hl_group = "DiffModifiedLine"
    else
      hl_group = nil
    end
    
    if hl_group then
      vim.api.nvim_buf_add_highlight(bufnr, ns, hl_group, meta.line, 0, -1)
    end
  end
  
  -- Apply character-level highlights (two-tier system)
  -- Note: Highlights are applied in order, so line backgrounds first, then character ranges
  -- This creates the "deeper color" effect where changed chars stand out
  for _, hl in ipairs(render_plan.char_highlights) do
    local hl_group
    if hl.type == 0 then -- HL_ADDED_LINE (light green background)
      hl_group = "DiffAddedLine"
    elseif hl.type == 1 then -- HL_REMOVED_LINE (light red background)
      hl_group = "DiffRemovedLine"
    elseif hl.type == 2 then -- HL_ADDED_CHAR (DEEP GREEN - the key feature!)
      hl_group = "DiffAddedChar"
    elseif hl.type == 3 then -- HL_REMOVED_CHAR (DEEP RED - the key feature!)
      hl_group = "DiffRemovedChar"
    elseif hl.type == 4 then -- HL_MODIFIED_LINE
      hl_group = "DiffModifiedLine"
    end
    
    if hl_group then
      vim.api.nvim_buf_add_highlight(bufnr, ns, hl_group, hl.line, hl.col_start, hl.col_end)
    end
  end
  
  -- Apply filler lines (virtual text)
  for _, filler in ipairs(render_plan.filler_lines) do
    for i = 1, filler.count do
      vim.api.nvim_buf_set_extmark(bufnr, ns, filler.line_after, 0, {
        virt_lines = { { { string.rep(" ", 80), "Normal" } } },
        virt_lines_above = false
      })
    end
  end
end

-- Open diff view with two buffers side-by-side
function M.open_diff_view(lines_a, lines_b, render_plan)
  setup_highlight_groups()
  
  -- Create left buffer
  local buf_left = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_left, 0, -1, false, lines_a)
  vim.bo[buf_left].modifiable = false
  vim.bo[buf_left].readonly = true
  
  -- Create right buffer
  local buf_right = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_right, 0, -1, false, lines_b)
  vim.bo[buf_right].modifiable = false
  vim.bo[buf_right].readonly = true
  
  -- Open vertical split
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf_left)
  vim.cmd("wincmd l")
  vim.api.nvim_win_set_buf(0, buf_right)
  
  -- Apply render plans
  M.apply_render_plan(buf_left, render_plan.left)
  M.apply_render_plan(buf_right, render_plan.right)
  
  -- Sync scrolling
  vim.wo.scrollbind = true
  vim.cmd("wincmd h")
  vim.wo.scrollbind = true
  vim.cmd("wincmd l")
end

return M
```

**Validation:** Test in Neovim interactively.

---

### **Step 8: Plugin Entry Point & Lazy.nvim Integration**

**Objective:** Create plugin entry point and make it installable via Lazy.nvim.

**Create `plugin/vscode-diff.lua`:**
```lua
-- Plugin entry point for Lazy.nvim

local diff = require("vscode-diff")
local render = require("vscode-diff.render")

-- User command to open diff
vim.api.nvim_create_user_command("VscodeDiff", function(opts)
  local file_a = opts.fargs[1]
  local file_b = opts.fargs[2]
  
  if not file_a or not file_b then
    vim.notify("Usage: :VscodeDiff <file_a> <file_b>", vim.log.levels.ERROR)
    return
  end
  
  -- Read files
  local lines_a = vim.fn.readfile(file_a)
  local lines_b = vim.fn.readfile(file_b)
  
  -- Compute diff
  local render_plan = diff.compute_diff(lines_a, lines_b)
  
  -- Open diff view
  render.open_diff_view(lines_a, lines_b, render_plan)
end, { nargs = "*" })
```

**Create `README.md`:**
```markdown
# nvim-vscode-diff

VSCode-style inline diff rendering for Neovim.

## Installation

Using [Lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "yourusername/nvim-vscode-diff",
  build = "make",
  config = function()
    -- Plugin is ready to use
  end
}
```

## Usage

```vim
:VscodeDiff file_a.txt file_b.txt
```

## Development

Build the C module:

```bash
make clean && make
```

Run tests:

```bash
make test  # C tests
nvim --headless -c "luafile tests/test_render.lua" -c "quit"  # Lua tests
```
```

**Validation:**
```bash
# Install plugin with Lazy.nvim (manual test)
# Open nvim, run :Lazy, add the plugin

# Or test locally:
nvim -c "set rtp+=." -c "VscodeDiff tests/fixtures/file_a.txt tests/fixtures/file_b.txt"
```

---

### **Step 9: End-to-End Testing**

**Objective:** Comprehensive E2E test with headless Neovim.

**Create `tests/e2e_test.lua`:**
```lua
-- E2E test script
vim.o.loadplugins = true
vim.cmd("set rtp+=.")

local diff = require("vscode-diff")
local render = require("vscode-diff.render")

print("=== E2E Test ===")

-- Test 1: Version
print("Version: " .. diff.get_version())
assert(diff.get_version() == "0.1.0", "Version mismatch")

-- Test 2: Diff computation
local lines_a = { "line1", "line2", "line3" }
local lines_b = { "line1", "line2_modified", "line3" }

local plan = diff.compute_diff(lines_a, lines_b)
assert(#plan.left.line_metadata == 3, "Left metadata count mismatch")
assert(#plan.right.line_metadata == 3, "Right metadata count mismatch")

print("✓ All E2E tests passed!")
vim.cmd("quit")
```

**Validation:**
```bash
nvim --headless -c "luafile tests/e2e_test.lua"

# Expected output:
# === E2E Test ===
# Version: 0.1.0
# ✓ All E2E tests passed!
```

---

## 🚀 Deployment Checklist

After completing all steps:

- [ ] C module compiles without errors (`make clean && make`)
- [ ] C tests pass (`make test`)
- [ ] Lua FFI loads successfully
- [ ] Lua tests pass (headless nvim)
- [ ] E2E test passes
- [ ] Plugin installs via Lazy.nvim
- [ ] `:VscodeDiff` command works interactively
- [ ] Highlight colors match VSCode
- [ ] Line alignment is correct
- [ ] Both buffers are read-only
- [ ] Scrollbind works

---

## 📝 Notes for Code Agent

1. **Incremental Testing:** After each step, run validation commands to ensure correctness.
2. **C Implementation:** Steps 3-5 use simplified stubs. For production, implement full Myers diff and character-level LCS.
3. **Memory Safety:** Ensure all `malloc`/`calloc` calls have corresponding `free` calls.
4. **Cross-Platform:** Test on Linux, macOS, and Windows. Adjust `Makefile` if needed.
5. **VSCode Parity:** When implementing full diff algorithms, refer to VSCode source for logic, but implement in C.
6. **Error Handling:** Add proper error handling in C (null checks, bounds checks).
7. **Performance:** For large files (>10k lines), consider optimizations (e.g., skip unchanged regions).

---

## 📚 VSCode Source References

Key files to study (don't copy code, just understand logic):

- **Diff Algorithm:** `src/vs/editor/common/diff/algorithms/myersDiffAlgorithm.ts`
- **Line Diff:** `src/vs/editor/common/diff/standardLinesDiffComputer.ts`
- **Character Diff:** `src/vs/editor/common/diff/algorithms/diffAlgorithm.ts`
- **Rendering:** `src/vs/editor/browser/widget/diffEditorWidget.ts`
- **Decorations:** `src/vs/editor/browser/widget/diffEditorDecorations.ts`

---

## ✅ Success Criteria

The MVP is complete when:

1. You can run `:VscodeDiff file_a.txt file_b.txt`
2. Two side-by-side buffers appear
3. Line backgrounds show red/green/blue for changes
4. Character-level highlights show within modified lines
5. Lines are aligned (filler lines inserted as needed)
6. Buffers are read-only
7. All tests pass (C unit tests, Lua tests, E2E test)

---

**Good luck! 🎯**
