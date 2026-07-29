#!/usr/bin/env bash
# Test runner for codediff.nvim using the in-tree test framework
# (tests/framework/), which replaces plenary.nvim.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          codediff.nvim Test Suite                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

cd "$PROJECT_ROOT"

# Run all spec files
FAILED=0

# Auto-discover all *_spec.lua files (POSIX-compatible)
SPEC_FILES=()
while IFS= read -r file; do
  SPEC_FILES+=("$file")
done < <(find tests -name '*_spec.lua' -type f | sort)

for spec_file in "${SPEC_FILES[@]}"; do
  echo -e "${CYAN}Running: $spec_file${NC}"
  if nvim --headless --noplugin -u tests/init.lua \
    -c "lua require('tests.framework').run_and_exit('$spec_file')" 2>&1; then
    echo ""
  else
    echo -e "${RED}✗ $spec_file failed${NC}"
    FAILED=$((FAILED + 1))
    echo ""
  fi
done

# Summary
echo "╔══════════════════════════════════════════════════════════════╗"
if [ $FAILED -eq 0 ]; then
  echo -e "║ ${GREEN}✓ ALL TESTS PASSED${NC}                                           ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  exit 0
else
  echo -e "║ ${RED}✗ $FAILED TEST(S) FAILED${NC}                                        ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  exit 1
fi
