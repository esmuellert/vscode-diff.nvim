#!/usr/bin/env bash
# E2E Test Runner
# Runs all E2E test cases and outputs render plans for human validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "════════════════════════════════════════════════════════════════════════════════"
echo "                              E2E TEST SUITE"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Check for verbose flag
VERBOSE=""
if [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
  VERBOSE="-v"
  echo "*** VERBOSE MODE ENABLED ***"
  echo ""
fi

# Run each test case
for test_dir in "$FIXTURES_DIR"/*; do
  if [ ! -d "$test_dir" ]; then
    continue
  fi
  
  test_name=$(basename "$test_dir")
  left_file="$test_dir/left.txt"
  right_file="$test_dir/right.txt"
  
  if [ ! -f "$left_file" ] || [ ! -f "$right_file" ]; then
    echo -e "${YELLOW}⚠ Skipping $test_name: missing files${NC}"
    continue
  fi
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${CYAN}TEST CASE: $test_name${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Left file:  $left_file"
  echo "Right file: $right_file"
  echo ""
  
  # Run the test
  nvim --headless -c "luafile $SCRIPT_DIR/run_case.lua" -- "$left_file" "$right_file" $VERBOSE
  
  echo ""
done

echo "════════════════════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ All E2E test cases completed${NC}"
echo "════════════════════════════════════════════════════════════════════════════════"
