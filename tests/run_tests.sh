#!/usr/bin/env bash
# Test runner for codediff.nvim using the in-tree test framework
# (tests/framework/), which replaces plenary.nvim.
#
# Discovery, concurrency and output grouping all live in
# tests/framework/supervisor.lua, so this script is a thin wrapper around a
# single Neovim invocation and stays identical to tests/run_tests.cmd.
#
# Env:
#   CODEDIFF_TEST_JOBS     concurrent spec workers (default: 2x CPUs, max 16)
#   CODEDIFF_TEST_TIMEOUT  per-spec timeout in ms (default: 300000)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

exec nvim --headless --noplugin -u tests/init.lua \
  -c "lua require('tests.framework').run_all_and_exit()"
