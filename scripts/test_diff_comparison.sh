#!/bin/bash

# Test script to compare C diff tool and Node vscode-diff.mjs outputs
# Tests 200 comparisons: 100 from Makefile versions, 100 from render.lua versions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE_DIR="$REPO_ROOT/example"
C_DIFF="$REPO_ROOT/c-diff-core/build/diff"
NODE_DIFF="$REPO_ROOT/vscode-diff.mjs"
TEMP_DIR="/tmp/diff_comparison_$$"

mkdir -p "$TEMP_DIR"

# Get all Makefile and render.lua versions sorted by filename
MAKEFILE_FILES=($(ls -1 "$EXAMPLE_DIR"/Makefile_* 2>/dev/null | sort))
RENDER_FILES=($(ls -1 "$EXAMPLE_DIR"/render.lua_* 2>/dev/null | sort))
NUM_MAKEFILE=${#MAKEFILE_FILES[@]}
NUM_RENDER=${#RENDER_FILES[@]}

echo "Found $NUM_MAKEFILE Makefile versions"
echo "Found $NUM_RENDER render.lua versions"
echo "C diff tool: $C_DIFF"
echo "Node diff tool: $NODE_DIFF"
echo ""

TOTAL_TESTS=0
MISMATCHES=0
MISMATCH_DETAILS=""

# Function to test a pair of files
test_pair() {
    local FILE1="$1"
    local FILE2="$2"
    local TEST_ID="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Get base filenames for display
    BASE1=$(basename "$FILE1")
    BASE2=$(basename "$FILE2")
    
    # Run C diff tool
    C_OUTPUT="$TEMP_DIR/c_output_${TEST_ID}.txt"
    "$C_DIFF" "$FILE1" "$FILE2" > "$C_OUTPUT" 2>&1
    C_EXIT=$?
    
    # Run Node diff tool
    NODE_OUTPUT="$TEMP_DIR/node_output_${TEST_ID}.txt"
    node "$NODE_DIFF" "$FILE1" "$FILE2" > "$NODE_OUTPUT" 2>&1
    NODE_EXIT=$?
    
    # Compare outputs
    if ! diff -q "$C_OUTPUT" "$NODE_OUTPUT" > /dev/null 2>&1; then
        MISMATCHES=$((MISMATCHES + 1))
        MISMATCH_DETAILS="${MISMATCH_DETAILS}Mismatch #${MISMATCHES} (Test #${TOTAL_TESTS}):\n"
        MISMATCH_DETAILS="${MISMATCH_DETAILS}  Files: $BASE1 vs $BASE2\n"
        MISMATCH_DETAILS="${MISMATCH_DETAILS}  C exit: $C_EXIT, Node exit: $NODE_EXIT\n"
        MISMATCH_DETAILS="${MISMATCH_DETAILS}  C output: $C_OUTPUT\n"
        MISMATCH_DETAILS="${MISMATCH_DETAILS}  Node output: $NODE_OUTPUT\n\n"
    fi
    
    # Progress indicator every 10 tests
    if [ $((TOTAL_TESTS % 10)) -eq 0 ]; then
        echo "Progress: $TOTAL_TESTS tests completed, $MISMATCHES mismatches found"
    fi
}

# Test Makefile pairs (first 100 tests)
echo "Testing Makefile versions (target: 100 tests)..."
for ((i=0; i<$NUM_MAKEFILE && TOTAL_TESTS<100; i++)); do
    for ((j=i+1; j<$NUM_MAKEFILE && TOTAL_TESTS<100; j++)); do
        test_pair "${MAKEFILE_FILES[$i]}" "${MAKEFILE_FILES[$j]}" "makefile_${i}_${j}"
    done
done

# Test render.lua pairs (next 100 tests)
echo "Testing render.lua versions (target: 100 more tests)..."
TESTS_BEFORE_RENDER=$TOTAL_TESTS
for ((i=0; i<$NUM_RENDER && TOTAL_TESTS<200; i++)); do
    for ((j=i+1; j<$NUM_RENDER && TOTAL_TESTS<200; j++)); do
        test_pair "${RENDER_FILES[$i]}" "${RENDER_FILES[$j]}" "render_${i}_${j}"
    done
done

echo ""
echo "========================================"
echo "SUMMARY"
echo "========================================"
echo "Total tests run: $TOTAL_TESTS"
echo "Mismatches found: $MISMATCHES"
echo ""

if [ $MISMATCHES -gt 0 ]; then
    echo "MISMATCH DETAILS:"
    echo "========================================"
    echo -e "$MISMATCH_DETAILS"
    echo ""
    echo "Showing first mismatch in detail:"
    echo "========================================"
    
    # Show first mismatch
    FIRST_C=$(ls -1 "$TEMP_DIR"/c_output_*.txt 2>/dev/null | head -1)
    FIRST_NODE="${FIRST_C/c_output/node_output}"
    
    if [ -f "$FIRST_C" ] && [ -f "$FIRST_NODE" ]; then
        echo "C diff output:"
        echo "---"
        head -50 "$FIRST_C"
        echo ""
        echo "Node diff output:"
        echo "---"
        head -50 "$FIRST_NODE"
        echo ""
        echo "Diff between outputs:"
        echo "---"
        diff -u "$FIRST_C" "$FIRST_NODE" | head -100
    fi
else
    echo "✓ All tests passed! No mismatches found."
fi

# Cleanup
rm -rf "$TEMP_DIR"

exit $MISMATCHES
