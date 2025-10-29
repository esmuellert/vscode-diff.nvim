#!/bin/bash

# Test script to compare C diff tool and Node vscode-diff.mjs outputs
# Tests at least 100 comparisons between different versions of Makefile

REPO_ROOT="/home/yanuoma/.local/share/nvim/vscode-diff.nvim"
EXAMPLE_DIR="$REPO_ROOT/example"
C_DIFF="$REPO_ROOT/c-diff-core/build/diff"
NODE_DIFF="$REPO_ROOT/vscode-diff.mjs"
TEMP_DIR="/tmp/diff_comparison_$$"

mkdir -p "$TEMP_DIR"

# Get all Makefile versions sorted by filename
FILES=($(ls -1 "$EXAMPLE_DIR"/Makefile_* | sort))
NUM_FILES=${#FILES[@]}

echo "Found $NUM_FILES Makefile versions"
echo "C diff tool: $C_DIFF"
echo "Node diff tool: $NODE_DIFF"
echo ""

TOTAL_TESTS=0
MISMATCHES=0
MISMATCH_DETAILS=""

# Test all pairs of files
for ((i=0; i<$NUM_FILES; i++)); do
    for ((j=i+1; j<$NUM_FILES; j++)); do
        FILE1="${FILES[$i]}"
        FILE2="${FILES[$j]}"
        
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        # Get base filenames for display
        BASE1=$(basename "$FILE1")
        BASE2=$(basename "$FILE2")
        
        # Run C diff tool
        C_OUTPUT="$TEMP_DIR/c_output_${i}_${j}.txt"
        "$C_DIFF" "$FILE1" "$FILE2" > "$C_OUTPUT" 2>&1
        C_EXIT=$?
        
        # Run Node diff tool
        NODE_OUTPUT="$TEMP_DIR/node_output_${i}_${j}.txt"
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
        
        # Stop early if we've done at least 100 tests
        if [ $TOTAL_TESTS -ge 100 ]; then
            break 2
        fi
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
