@echo off
REM E2E scenario runner for codediff.nvim (Windows).
REM
REM Each tests/e2e/*.lua scenario is a table with { setup, run, validate,
REM cleanup } phases, driven by scripts/nvim-e2e.lua. This wrapper runs every
REM scenario in its own Neovim process (matching the *_spec framework's
REM isolation) and returns non-zero if any scenario fails. Kept in sync with
REM tests/run_e2e.sh.

setlocal enabledelayedexpansion
pushd "%~dp0.."

set /a TOTAL=0
set /a PASSED=0
set /a FAILED=0
set FAILED_NAMES=

for %%F in (tests\e2e\*.lua) do (
  set /a TOTAL+=1
  set NAME=%%~nF
  <nul set /p="[e2e] !NAME! "

  set SCENARIO_FILE=%%F
  call nvim --headless --noplugin -u tests/init.lua ^
    -c "luafile scripts/nvim-e2e.lua" -c "qa!" > "%TEMP%\e2e_!NAME!.log" 2>&1
  if !ERRORLEVEL! EQU 0 (
    echo PASS
    set /a PASSED+=1
  ) else (
    echo FAIL
    set /a FAILED+=1
    set FAILED_NAMES=!FAILED_NAMES! !NAME!
    echo --- %%F output ---
    type "%TEMP%\e2e_!NAME!.log"
    echo --- end %%F output ---
  )
)

echo.
echo E2E: !PASSED! passed, !FAILED! failed of !TOTAL! scenarios
if !FAILED! GTR 0 (
  echo Failed scenarios:!FAILED_NAMES!
  set EXIT_CODE=1
) else (
  set EXIT_CODE=0
)

popd
exit /b %EXIT_CODE%
