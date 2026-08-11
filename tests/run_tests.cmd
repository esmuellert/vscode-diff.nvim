@echo off
REM Test runner for codediff.nvim using the in-tree test framework
REM (tests/framework/), which replaces plenary.nvim. (Windows)
REM
REM Discovery, concurrency and output grouping all live in
REM tests/framework/supervisor.lua, so this script is a thin wrapper around a
REM single Neovim invocation and stays identical to tests/run_tests.sh.
REM
REM Env:
REM   CODEDIFF_TEST_JOBS     concurrent spec workers (default: 2x CPUs, max 16)
REM   CODEDIFF_TEST_TIMEOUT  per-spec timeout in ms (default: 300000)

setlocal
pushd "%~dp0.."

nvim --headless --noplugin -u tests/init.lua -c "lua require('tests.framework').run_all_and_exit()"
set EXIT_CODE=%ERRORLEVEL%

popd
exit /b %EXIT_CODE%
