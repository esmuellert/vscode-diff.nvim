#!/usr/bin/env bash
# E2E scenario runner for codediff.nvim.
#
# Each `tests/e2e/*.lua` scenario is a table with { setup, run, validate,
# cleanup } phases, driven by `scripts/nvim-e2e.lua`. This wrapper runs every
# scenario in its own Neovim process (matches the isolation the *_spec
# framework already gets) and returns non-zero if any scenario fails.
#
# CI parses only the final line of stdout for the summary; individual
# scenario output goes to stderr for the human reader / build log.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

scenarios=(tests/e2e/*.lua)
if [ ${#scenarios[@]} -eq 0 ]; then
  echo "No E2E scenarios found under tests/e2e/"
  exit 0
fi

total=${#scenarios[@]}
passed=0
failed=0
failed_names=()

for scenario in "${scenarios[@]}"; do
  name="$(basename "$scenario" .lua)"
  printf '[e2e] %-40s ' "$name" >&2

  # Run each scenario in isolation. `--noplugin -u tests/init.lua` matches
  # the *_spec bootstrap so scenarios see the same runtime environment.
  # SCENARIO_FILE triggers the auto-run branch at the bottom of nvim-e2e.lua
  # which cquit(1)s on failure, giving us a reliable exit code.
  if SCENARIO_FILE="$scenario" \
     nvim --headless --noplugin -u tests/init.lua \
       -c "luafile scripts/nvim-e2e.lua" \
       -c "qa!" >/tmp/e2e_${name}.log 2>&1; then
    echo "PASS" >&2
    passed=$((passed + 1))
  else
    echo "FAIL" >&2
    failed=$((failed + 1))
    failed_names+=("$name")
    # Surface the failing scenario's output so the CI log has the diagnostic.
    echo "--- $scenario output ---" >&2
    cat "/tmp/e2e_${name}.log" >&2
    echo "--- end $scenario output ---" >&2
  fi
done

echo "" >&2
echo "E2E: $passed passed, $failed failed of $total scenarios"
if [ $failed -gt 0 ]; then
  echo "Failed scenarios: ${failed_names[*]}" >&2
  exit 1
fi
exit 0
