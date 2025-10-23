#!/usr/bin/env bash
# Master Test Runner
# Runs all tests (C unit, Lua unit, E2E)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                           VSCODE-DIFF TEST SUITE                            ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

VERBOSE=""
if [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
  VERBOSE="-v"
  echo -e "${YELLOW}*** VERBOSE MODE ENABLED ***${NC}"
  echo ""
fi

TOTAL_FAILED=0

# 1. C Unit Tests
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│ Step 1/3: C Unit Tests                                                      │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
echo ""

cd "$PROJECT_ROOT"
if make test-c 2>&1 | grep -v "^make"; then
  echo -e "${GREEN}✓ C unit tests passed${NC}"
else
  echo -e "${RED}✗ C unit tests failed${NC}"
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
echo ""

# 2. Lua Unit Tests
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│ Step 2/3: Lua Unit Tests                                                    │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
echo ""

if "$SCRIPT_DIR/unit/run_all.sh"; then
  echo -e "${GREEN}✓ Lua unit tests passed${NC}"
else
  echo -e "${RED}✗ Lua unit tests failed${NC}"
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
echo ""

# 3. E2E Tests
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│ Step 3/3: E2E Tests                                                         │"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
echo ""

if "$SCRIPT_DIR/e2e/run_all.sh" $VERBOSE; then
  echo -e "${GREEN}✓ E2E tests completed${NC}"
else
  echo -e "${RED}✗ E2E tests failed${NC}"
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
echo ""

# Summary
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
if [ $TOTAL_FAILED -eq 0 ]; then
  echo -e "║ ${GREEN}✓ ALL TESTS PASSED${NC}                                                          ║"
  echo "╚══════════════════════════════════════════════════════════════════════════════╝"
  exit 0
else
  echo -e "║ ${RED}✗ $TOTAL_FAILED TEST SUITE(S) FAILED${NC}                                                  ║"
  echo "╚══════════════════════════════════════════════════════════════════════════════╝"
  exit 1
fi
