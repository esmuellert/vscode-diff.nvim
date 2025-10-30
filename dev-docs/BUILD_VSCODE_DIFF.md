# VSCode Diff Extraction Tool

This script extracts and bundles VSCode's diff algorithm into a standalone JavaScript executable.

## Quick Start

```bash
# Generate the standalone diff tool
./scripts/build-vscode-diff.sh

# This creates: vscode-diff.mjs (default name)
# Or specify a custom name:
./scripts/build-vscode-diff.sh my-diff-tool.mjs
```

## Usage

```bash
node vscode-diff.mjs <file1> <file2>
```

## Example

```bash
# Create test files
echo "line1" > test1.txt
echo "line2" > test2.txt

# Run diff
node vscode-diff.mjs test1.txt test2.txt
```

## Output

The tool outputs the exact same format as the C implementation's `print_linesdiff` function:

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

## Requirements

- Node.js (for running the generated tool)
- npm (for esbuild during build process)
- Git (for cloning VSCode repo)

## What It Does

1. Clones VSCode repository (sparse checkout for minimal size)
2. Extracts only the diff algorithm files (~260 source files)
3. Creates a wrapper script for CLI usage
4. Bundles everything into a single ~239KB JavaScript file
5. Cleans up temporary files

## Use Cases

- **Reference implementation** for testing
- **Source of truth** for validation
- **Debugging tool** for comparing outputs
- **Standalone diff** without installing VSCode

## Technical Details

- **Bundle size:** ~239KB
- **Build time:** ~20-30 seconds (includes git clone)
- **Output format:** ESM (requires Node.js with ESM support)
- **Algorithm:** Same as VSCode's DefaultLinesDiffComputer

## See Also

- [VSCode Extraction Summary](dev-docs/vscode-extraction-summary.md) - Detailed feasibility study
- [VSCode Source](https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts) - Original algorithm
