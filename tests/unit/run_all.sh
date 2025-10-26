#!/usr/bin/env bash
# Unit Test Runner
# Runs all unit tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "════════════════════════════════════════════════════════════════════════════════"
echo "                             UNIT TEST SUITE"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

FAILED=0
PASSED=0

# Run each unit test
for test_file in "$SCRIPT_DIR"/*.lua; do
  if [ ! -f "$test_file" ]; then
    continue
  fi
  
  test_name=$(basename "$test_file" .lua)
  
  echo -e "${CYAN}Running: $test_name${NC}"
  
  if nvim --headless -c "luafile $test_file" -c "quit" 2>&1; then
    PASSED=$((PASSED + 1))
  else
    echo -e "${RED}✗ FAILED: $test_name${NC}"
    FAILED=$((FAILED + 1))
  fi
  
  echo ""
done

echo "════════════════════════════════════════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All $PASSED unit tests passed${NC}"
  exit 0
else
  echo -e "${RED}✗ $FAILED test(s) failed, $PASSED passed${NC}"
  exit 1
fi
