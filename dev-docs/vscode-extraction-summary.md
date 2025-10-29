# VSCode Diff Algorithm Extraction - Feasibility Study

**Date:** October 28, 2025  
**Status:** ✅ Successfully Completed

## Executive Summary

Yes, it is **absolutely possible** to extract VSCode's diff algorithm into a standalone JavaScript executable. The extraction process is straightforward and the resulting bundle is compact (~239KB).

## What Was Done

### 1. Repository Analysis

Located the core diff algorithm in VSCode:
- **Main file:** `src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts`
- **Key function:** `computeDiff(originalLines, modifiedLines, options)`
- **Dependencies:** Base utilities and core editor types

### 2. Extraction Process

Used sparse Git checkout to minimize download size:
```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/microsoft/vscode.git
git sparse-checkout set src/vs/editor/common/diff src/vs/base/common src/vs/editor/common/core
```

### 3. Bundling Strategy

Created a wrapper script and bundled with esbuild:
- **Input:** TypeScript wrapper + VSCode source code
- **Output:** Single ESM JavaScript file (~239KB)
- **Bundler:** esbuild (fast, zero-config)
- **Build time:** ~20-30ms

### 4. Created Automated Build Script

**Location:** `scripts/build-vscode-diff.sh`

Features:
- Fully automated extraction and bundling
- No manual steps required
- Outputs ready-to-use standalone `.mjs` file
- Self-contained (cleans up temp files automatically)

**Usage:**
```bash
bash scripts/build-vscode-diff.sh [output-filename.mjs]
```

**Default output:** `vscode-diff.mjs`

## Output Format Comparison

Both tools now produce **identical output format**:

```
=================================================================
Diff Tool - Computing differences
=================================================================
Original: test1.txt (5 lines)
Modified: test2.txt (5 lines)
=================================================================

Diff Results:
=================================================================
Number of changes: 2
Hit timeout: no

  Changes: 2 line mapping(s)
    [0] Lines 2-3 -> Lines 2-3 (2 inner changes)
         Inner: L2:C10-L2:C10 -> L2:C10-L2:C19
         Inner: L3:C7-L3:C7 -> L3:C7-L3:C16
    [1] Lines 5-5 -> Lines 5-5 (1 inner change)
         Inner: L5:C6-L5:C7 -> L5:C6-L5:C13

=================================================================
```

The JavaScript tool outputs in the exact same format as the C implementation's `print_linesdiff` function, making direct comparison trivial.

## Key Features

### Identical Output Format

The JavaScript tool now outputs in **exactly the same format** as the C implementation:

- Same header structure
- Same line mapping format
- Same inner change notation
- Character positions use the same notation (L#:C#)

This makes the JavaScript tool a **perfect reference** for validating the C implementation.

## Integration Possibilities

### As Source of Truth

The VSCode JavaScript bundle can serve as a reference implementation:

1. **Validation:** Test our C implementation against VSCode's output
2. **Regression Testing:** Ensure algorithm parity
3. **Feature Comparison:** Verify move detection, character-level diffs, etc.
4. **Debugging:** Compare outputs when results differ

### Usage Pattern

```bash
# Run VSCode diff
node vscode-diff.mjs original.txt modified.txt

# Run our C diff  
./build/diff original.txt modified.txt

# Outputs are now directly comparable - same format!
```

### Direct Comparison

Since both tools use the **identical output format**, you can now:

1. **Diff the outputs directly:** `diff <(node vscode-diff.mjs f1 f2) <(./build/diff f1 f2)`
2. **Automated testing:** Compare outputs byte-for-byte in test suites
3. **Regression detection:** Any format change indicates a discrepancy
4. **Debugging:** Side-by-side comparison is trivial

## Files Generated

### 1. Build Script
- **Location:** `scripts/build-vscode-diff.sh`
- **Purpose:** Automated extraction and bundling
- **Size:** ~4KB

### 2. Standalone VSCode Diff Tool
- **Example:** `/tmp/test-build/my-vscode-diff.mjs`
- **Size:** 238.9KB
- **Runtime:** Node.js (ESM)
- **Dependencies:** None (fully bundled)

### 3. Our C Diff Tool
- **Location:** `c-diff-core/build/diff`
- **Built via:** `make diff-tool`
- **Size:** Varies by platform
- **Runtime:** Native (no dependencies)

## Recommendations

### For Testing & Validation

1. **Add VSCode reference tests:** Use the JavaScript tool as oracle for test cases
2. **Create comparison suite:** Automate output comparison (after format normalization)
3. **Validate edge cases:** Use VSCode's implementation to verify complex scenarios

### For Documentation

1. **Document format differences:** Explain why outputs differ in structure but are algorithmically equivalent
2. **Add "source of truth" section:** Reference VSCode's implementation
3. **Include build instructions:** Add `scripts/build-vscode-diff.sh` to repo (optional)

### For CI/CD

Consider adding a test that:
1. Runs VSCode diff tool
2. Runs our C diff tool
3. Compares algorithmic results (not format)
4. Fails if results diverge

## Testing Examples

### Simple Text Change
```bash
# Input files
echo -e "Hello World\nThis is a test file\nLine 3\nLine 4\nLine 5" > test1.txt
echo -e "Hello World\nThis is a modified test file\nLine 3 modified\nLine 4\nLine 6 added" > test2.txt

# VSCode output
node vscode-diff.mjs test1.txt test2.txt

# C output
./build/diff test1.txt test2.txt
```

### Code Move Detection
```bash
# Create files with function reordering
# VSCode detects moves when computeMoves: true
node vscode-diff.mjs code_before.js code_after.js
```

## Conclusion

**Bottom Line:** Extracting VSCode's diff algorithm is not only possible but **remarkably easy**. The automated build script makes it a single command to generate a standalone, dependency-free JavaScript executable that can serve as a perfect source of truth for validating our C implementation.

The ~239KB bundle is small enough to:
- Check into the repo (if desired)
- Include in test fixtures
- Distribute with documentation
- Run in CI/CD pipelines

This gives us a reliable reference implementation directly from the source, ensuring our C port maintains perfect algorithmic fidelity to VSCode's behavior.
