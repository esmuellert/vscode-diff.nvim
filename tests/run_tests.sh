#!/usr/bin/env bash
# Test runner for vscode-diff.nvim integration tests
# Runs focused tests for FFI boundary and Git integration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          vscode-diff.nvim Integration Test Suite             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

FAILED=0

# Test 1: FFI Integration
echo -e "${CYAN}Running: FFI Integration Tests${NC}"
if nvim --headless -c "luafile $SCRIPT_DIR/test_ffi_integration.lua" -c "qa!" 2>&1; then
  echo ""
else
  echo -e "${RED}✗ FFI integration tests failed${NC}"
  FAILED=$((FAILED + 1))
  echo ""
fi

# Test 2: Git Integration
echo -e "${CYAN}Running: Git Integration Tests${NC}"
if nvim --headless -c "luafile $SCRIPT_DIR/test_git_integration.lua" -c "qa!" 2>&1; then
  echo ""
else
  echo -e "${RED}✗ Git integration tests failed${NC}"
  FAILED=$((FAILED + 1))
  echo ""
fi

# Test 3: Auto-scroll
echo -e "${CYAN}Running: Auto-scroll Tests${NC}"
if nvim --headless -c "luafile $SCRIPT_DIR/test_autoscroll.lua" -c "qa!" 2>&1; then
  echo ""
else
  echo -e "${RED}✗ Auto-scroll tests failed${NC}"
  FAILED=$((FAILED + 1))
  echo ""
fi

# Summary
echo "╔══════════════════════════════════════════════════════════════╗"
if [ $FAILED -eq 0 ]; then
  echo -e "║ ${GREEN}✓ ALL INTEGRATION TESTS PASSED${NC}                             ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  exit 0
else
  echo -e "║ ${RED}✗ $FAILED TEST SUITE(S) FAILED${NC}                                  ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  exit 1
fi
