@echo off
REM Test runner for codediff.nvim using the in-tree test framework
REM (tests/framework/), which replaces plenary.nvim. (Windows)
setlocal enabledelayedexpansion

set FAILED=0

echo.
echo ================================================================
echo           codediff.nvim Test Suite
echo ================================================================
echo.

for /r tests %%f in (*_spec.lua) do (
    echo Running: %%f
    nvim --headless --noplugin -u tests/init.lua -c "lua require('tests.framework').run_and_exit('%%f')"
    if errorlevel 1 (
        echo FAILED: %%f
        set /a FAILED+=1
    )
    echo.
)

echo ================================================================
if !FAILED! equ 0 (
    echo ALL TESTS PASSED
    exit /b 0
) else (
    echo !FAILED! TEST(S^) FAILED
    exit /b 1
)
