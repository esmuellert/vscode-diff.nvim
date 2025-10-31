#!/bin/bash

# Test script to compare C diff tool and Node vscode-diff.mjs outputs
# Dynamically tests top N most revised files from git history (origin/main)
#
# Usage: ./test_diff_comparison.sh [-v|--verbose]
#   -v, --verbose    Show detailed mismatch information

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE_DIR="$REPO_ROOT/example"
C_DIFF="$REPO_ROOT/c-diff-core/build/diff"
NODE_DIFF="$REPO_ROOT/vscode-diff.mjs"
TEMP_DIR="/tmp/diff_comparison_$$"

# Configuration: Number of top revised files to test
NUM_TOP_FILES=10
TESTS_PER_FILE=30
# Use origin/main as the reference point for consistent results
BASE_REF="origin/main"
# Verbose mode for mismatch details (default: false)
VERBOSE=false

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-v|--verbose] [-h|--help]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed mismatch information"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

mkdir -p "$TEMP_DIR"

# Auto-build binaries if they don't exist
if [ ! -f "$C_DIFF" ]; then
    echo "C diff binary not found. Building..."
    cd "$REPO_ROOT/c-diff-core"
    make diff-tool
    if [ ! -f "$C_DIFF" ]; then
        echo "Error: Failed to build C diff binary"
        exit 1
    fi
    cd "$REPO_ROOT"
fi

if [ ! -f "$NODE_DIFF" ]; then
    echo "Node diff binary not found. Building..."
    "$SCRIPT_DIR/build-vscode-diff.sh"
    if [ ! -f "$NODE_DIFF" ]; then
        echo "Error: Failed to build Node diff binary"
        exit 1
    fi
fi

# Function to generate example files for top N most revised files
generate_example_files() {
    local num_files=$1
    echo "Generating example files for top $num_files most revised files from $BASE_REF..."
    
    # Create example directory
    mkdir -p "$EXAMPLE_DIR"
    
    # Get top N most revised files from git history up to BASE_REF
    # Note: --follow only works with single files, so we get the list first,
    # then count revisions with --follow for each file individually
    local files=($(git -C "$REPO_ROOT" log "$BASE_REF" --pretty=format: --name-only | \
        grep -v '^$' | sort | uniq -c | sort -rn | head -$num_files | awk '{print $2}'))
    
    echo "Top $num_files most revised files (as of $BASE_REF, with rename tracking):"
    for i in "${!files[@]}"; do
        local file="${files[$i]}"
        # Use --follow to track renames when counting revisions (works per-file)
        local revisions=$(git -C "$REPO_ROOT" log "$BASE_REF" --follow --oneline -- "$file" | wc -l)
        echo "  $((i+1)). $file ($revisions revisions)"
    done
    echo ""
    
    # For each top file, save all its git history versions up to BASE_REF
    for file in "${files[@]}"; do
        echo "Processing $file..."
        
        # Check if file exists at BASE_REF
        if ! git -C "$REPO_ROOT" cat-file -e "$BASE_REF:$file" 2>/dev/null; then
            echo "  Warning: $file not found at $BASE_REF, skipping"
            continue
        fi
        
        local basename=$(basename "$file")
        
        # Get all commits that modified this file up to BASE_REF (chronological order)
        # Use --follow to track file renames
        local commits=($(git -C "$REPO_ROOT" log "$BASE_REF" --reverse --follow --pretty=format:%H -- "$file"))
        
        echo "  Found ${#commits[@]} commits (saving in chronological order)"
        
        # Save each version with sequence number and commit hash for ordering
        local count=0
        for idx in "${!commits[@]}"; do
            local commit="${commits[$idx]}"
            # Use zero-padded index for proper sorting (e.g., 001, 002, ...)
            local seq=$(printf "%03d" $idx)
            local output_file="$EXAMPLE_DIR/${basename}_${seq}_${commit}"
            
            # Extract file content at this commit
            git -C "$REPO_ROOT" show "$commit:$file" > "$output_file" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                count=$((count + 1))
            else
                rm -f "$output_file"
            fi
        done
        
        echo "  Saved $count versions in chronological order"
    done
    
    echo ""
    echo "Done! Example files generated in $EXAMPLE_DIR"
    echo "Total files: $(ls -1 "$EXAMPLE_DIR" | wc -l)"
}

# Get top N most revised files from git history up to BASE_REF
echo "Finding top $NUM_TOP_FILES most revised files from git history (up to $BASE_REF)..."
# Note: Can't use --follow here as it requires a single pathspec
# We'll use --follow when counting individual file revisions
TOP_FILES=($(git -C "$REPO_ROOT" log "$BASE_REF" --pretty=format: --name-only | \
    grep -v '^$' | sort | uniq -c | sort -rn | head -$NUM_TOP_FILES | awk '{print $2}'))

# Check if we need to regenerate example files
NEED_REGENERATE=false
for TOP_FILE in "${TOP_FILES[@]}"; do
    BASENAME=$(basename "$TOP_FILE")
    FILES_COUNT=$(ls -1 "$EXAMPLE_DIR"/${BASENAME}_* 2>/dev/null | wc -l)
    if [ $FILES_COUNT -eq 0 ]; then
        NEED_REGENERATE=true
        break
    fi
done

if [ "$NEED_REGENERATE" = true ]; then
    echo "Example files missing or incomplete. Regenerating..."
    generate_example_files $NUM_TOP_FILES
    echo ""
fi

echo "Top revised files (as of $BASE_REF, with rename tracking):"
for i in "${!TOP_FILES[@]}"; do
    # Use --follow to track renames for each individual file
    REVISIONS=$(git -C "$REPO_ROOT" log "$BASE_REF" --follow --oneline -- "${TOP_FILES[$i]}" | wc -l)
    echo "  $((i+1)). ${TOP_FILES[$i]} ($REVISIONS revisions)"
done
echo ""

# Collect version files for each top file (skip files with 0 versions)
declare -a FILE_GROUPS
declare -a VALID_TOP_FILES
declare -A FILE_METRICS  # Store file metrics (lines, size)
for TOP_FILE in "${TOP_FILES[@]}"; do
    BASENAME=$(basename "$TOP_FILE")
    # Files are now named: basename_SEQ_HASH, sort by SEQ for chronological order
    FILES=($(ls -1 "$EXAMPLE_DIR"/${BASENAME}_* 2>/dev/null | sort))
    if [ ${#FILES[@]} -gt 0 ]; then
        FILE_GROUPS+=("${#FILES[@]}")
        eval "FILES_${BASENAME//[^a-zA-Z0-9]/_}=(${FILES[@]})"
        VALID_TOP_FILES+=("$TOP_FILE")
        
        # Get metrics from the latest version (last file in chronological order)
        LATEST_FILE="${FILES[-1]}"
        LINES=$(wc -l < "$LATEST_FILE" 2>/dev/null || echo "0")
        SIZE_BYTES=$(stat -f%z "$LATEST_FILE" 2>/dev/null || stat -c%s "$LATEST_FILE" 2>/dev/null || echo "0")
        SIZE_KB=$(awk "BEGIN {printf \"%.1f\", $SIZE_BYTES/1024}")
        FILE_METRICS["$BASENAME"]="${LINES}L ${SIZE_KB}KB"
        
        echo "Found ${#FILES[@]} versions of $BASENAME (chronologically ordered)"
    fi
done
echo ""

# Update TOP_FILES to only include files with versions
TOP_FILES=("${VALID_TOP_FILES[@]}")

TOTAL_TESTS=0
MISMATCHES=0
MISMATCH_DETAILS=""

# Timing arrays per file
declare -A C_TIMES
declare -A NODE_TIMES
declare -A TEST_COUNTS

# Function to test a pair of files
test_pair() {
    local FILE1="$1"
    local FILE2="$2"
    local TEST_ID="$3"
    local FILE_GROUP="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Get base filenames for display
    BASE1=$(basename "$FILE1")
    BASE2=$(basename "$FILE2")
    
    # Run C diff tool with timing
    C_OUTPUT="$TEMP_DIR/c_output_${TEST_ID}.txt"
    C_START=$(date +%s%N)
    "$C_DIFF" "$FILE1" "$FILE2" > "$C_OUTPUT" 2>&1
    C_EXIT=$?
    C_END=$(date +%s%N)
    C_TIME=$(( (C_END - C_START) / 1000000 )) # Convert to milliseconds
    
    # Run Node diff tool with timing
    NODE_OUTPUT="$TEMP_DIR/node_output_${TEST_ID}.txt"
    NODE_START=$(date +%s%N)
    node "$NODE_DIFF" "$FILE1" "$FILE2" > "$NODE_OUTPUT" 2>&1
    NODE_EXIT=$?
    NODE_END=$(date +%s%N)
    NODE_TIME=$(( (NODE_END - NODE_START) / 1000000 )) # Convert to milliseconds
    
    # Accumulate timing stats
    C_TIMES[$FILE_GROUP]=$((${C_TIMES[$FILE_GROUP]:-0} + C_TIME))
    NODE_TIMES[$FILE_GROUP]=$((${NODE_TIMES[$FILE_GROUP]:-0} + NODE_TIME))
    TEST_COUNTS[$FILE_GROUP]=$((${TEST_COUNTS[$FILE_GROUP]:-0} + 1))
    
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

# Test each file group with real-world commit distances
for FILE_IDX in "${!TOP_FILES[@]}"; do
    TOP_FILE="${TOP_FILES[$FILE_IDX]}"
    BASENAME=$(basename "$TOP_FILE")
    VAR_NAME="FILES_${BASENAME//[^a-zA-Z0-9]/_}[@]"
    eval "FILE_ARRAY=(\${$VAR_NAME})"
    NUM_FILES=${#FILE_ARRAY[@]}
    
    echo "Testing $BASENAME versions (target: $TESTS_PER_FILE tests)..."
    echo "  Strategy: consecutive commits first, then increasing distances"
    TESTS_BEFORE=$TOTAL_TESTS
    
    # Test with increasing commit distances: 1, 2, 3, 4, 5, ...
    # This simulates real-world usage where users typically diff nearby commits
    for ((distance=1; distance<$NUM_FILES && (TOTAL_TESTS - TESTS_BEFORE)<$TESTS_PER_FILE; distance++)); do
        # For each distance, test all consecutive pairs with that distance
        for ((i=0; i+distance<$NUM_FILES && (TOTAL_TESTS - TESTS_BEFORE)<$TESTS_PER_FILE; i++)); do
            j=$((i + distance))
            test_pair "${FILE_ARRAY[$i]}" "${FILE_ARRAY[$j]}" "${BASENAME//[^a-zA-Z0-9]/_}_d${distance}_${i}_${j}" "$BASENAME"
        done
    done
    echo ""
done

echo ""
echo "========================================"
echo "SUMMARY"
echo "========================================"
echo "Total tests run: $TOTAL_TESTS"
echo "Mismatches found: $MISMATCHES"
echo ""

if [ $MISMATCHES -gt 0 ]; then
    if [ "$VERBOSE" = true ]; then
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
        echo "⚠ Mismatches detected. Run with -v or --verbose to see details."
    fi
else
    echo "✓ All tests passed! No mismatches found."
fi

echo ""
echo "========================================"
echo "PERFORMANCE COMPARISON"
echo "========================================"
for FILE_IDX in "${!TOP_FILES[@]}"; do
    TOP_FILE="${TOP_FILES[$FILE_IDX]}"
    BASENAME=$(basename "$TOP_FILE")
    
    if [ ${TEST_COUNTS[$BASENAME]:-0} -gt 0 ]; then
        C_AVG=$(( ${C_TIMES[$BASENAME]} / ${TEST_COUNTS[$BASENAME]} ))
        NODE_AVG=$(( ${NODE_TIMES[$BASENAME]} / ${TEST_COUNTS[$BASENAME]} ))
        
        # Include file metrics in the output
        METRICS="${FILE_METRICS[$BASENAME]}"
        echo "$BASENAME [$METRICS] (${TEST_COUNTS[$BASENAME]} tests):"
        echo "  C diff:    ${C_AVG} ms average"
        echo "  Node diff: ${NODE_AVG} ms average"
        
        if [ $C_AVG -gt 0 ]; then
            RATIO=$(( (NODE_AVG * 100) / C_AVG ))
            echo "  Node/C ratio: ${RATIO}%"
        fi
        echo ""
    fi
done

# Cleanup
rm -rf "$TEMP_DIR"

exit $MISMATCHES
