cmake_minimum_required(VERSION 3.15)
project(diff_core VERSION 0.3.0 LANGUAGES C)

# C Standard
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Platform detection
if(WIN32)
    set(PLATFORM_WINDOWS TRUE)
elseif(APPLE)
    set(PLATFORM_MACOS TRUE)
elseif(UNIX)
    set(PLATFORM_LINUX TRUE)
endif()

# Compiler flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")
set(CMAKE_C_FLAGS_DEBUG "-g -O0")
set(CMAKE_C_FLAGS_RELEASE "-O2 -DNDEBUG")

# POSIX flags for non-Windows
if(NOT WIN32)
    add_definitions(-D_POSIX_C_SOURCE=200809L)
endif()

# Find utf8proc library (or use bundled version)
set(UTF8PROC_BUNDLED "${CMAKE_CURRENT_SOURCE_DIR}/vendor/utf8proc.c")
if(EXISTS ${UTF8PROC_BUNDLED})
    message(STATUS "Using bundled utf8proc (no external dependency)")
    set(USE_BUNDLED_UTF8PROC TRUE)
    set(UTF8PROC_SOURCES ${UTF8PROC_BUNDLED})
    set(UTF8PROC_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}/vendor")
else()
    message(STATUS "Using system utf8proc")
    find_library(UTF8PROC_LIBRARY NAMES utf8proc)
    if(NOT UTF8PROC_LIBRARY)
        message(FATAL_ERROR "utf8proc library not found. Please install libutf8proc-dev or use bundled version.")
    endif()
    set(USE_BUNDLED_UTF8PROC FALSE)
endif()

# Source files for shared library
set(DIFF_CORE_SOURCES
    src/diff_api.c
    src/render_plan.c
    default_lines_diff_computer.c
    src/char_level.c
    src/line_level.c
    src/myers.c
    src/optimize.c
    src/sequence.c
    src/range_mapping.c
    src/string_hash_map.c
    src/utils.c
    src/print_utils.c
    src/utf8_utils.c
)

# Add bundled utf8proc if using it
if(USE_BUNDLED_UTF8PROC)
    list(APPEND DIFF_CORE_SOURCES ${UTF8PROC_SOURCES})
endif()

# Shared library target
add_library(diff_core SHARED ${DIFF_CORE_SOURCES})

target_include_directories(diff_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        $<$<BOOL:${USE_BUNDLED_UTF8PROC}>:${UTF8PROC_INCLUDE}>
)

if(USE_BUNDLED_UTF8PROC)
    # Using bundled utf8proc - no external linking needed
    target_link_libraries(diff_core PRIVATE m)
else()
    # Using system utf8proc
    target_link_libraries(diff_core PRIVATE ${UTF8PROC_LIBRARY})
endif()

# Platform-specific library naming
if(WIN32)
    set_target_properties(diff_core PROPERTIES OUTPUT_NAME "diff_core")
    set_target_properties(diff_core PROPERTIES SUFFIX ".dll")
elseif(APPLE)
    set_target_properties(diff_core PROPERTIES OUTPUT_NAME "diff_core")
    set_target_properties(diff_core PROPERTIES SUFFIX ".dylib")
else()
    set_target_properties(diff_core PROPERTIES OUTPUT_NAME "diff_core")
    set_target_properties(diff_core PROPERTIES SUFFIX ".so")
endif()

# Install to parent directory (for Lua FFI)
set(INSTALL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/..)
install(TARGETS diff_core
    LIBRARY DESTINATION ${INSTALL_DIR}
    RUNTIME DESTINATION ${INSTALL_DIR}
)

# Custom install target that copies immediately
add_custom_command(TARGET diff_core POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:diff_core>
        ${INSTALL_DIR}/libdiff_core$<TARGET_FILE_SUFFIX:diff_core>
    COMMENT "Installing library to plugin root"
)

# Testing
enable_testing()

# Test source files (common dependencies)
set(TEST_COMMON_SOURCES
    src/utils.c
    src/print_utils.c
    src/string_hash_map.c
    src/sequence.c
    src/myers.c
    src/optimize.c
    src/line_level.c
    src/char_level.c
    src/range_mapping.c
    src/render_plan.c
    src/diff_api.c
    src/utf8_utils.c
    default_lines_diff_computer.c
)

# Add bundled utf8proc to tests if using it
if(USE_BUNDLED_UTF8PROC)
    list(APPEND TEST_COMMON_SOURCES ${UTF8PROC_SOURCES})
endif()

# Helper function to add tests
function(add_diff_test test_name)
    add_executable(${test_name} tests/${test_name}.c ${TEST_COMMON_SOURCES})
    target_include_directories(${test_name} PRIVATE include)
    
    if(USE_BUNDLED_UTF8PROC)
        target_include_directories(${test_name} PRIVATE ${UTF8PROC_INCLUDE})
        target_link_libraries(${test_name} PRIVATE m)
    else()
        target_link_libraries(${test_name} PRIVATE ${UTF8PROC_LIBRARY} m)
    endif()
    
    add_test(NAME ${test_name} COMMAND ${test_name})
endfunction()

# Add all tests
add_diff_test(test_myers)
add_diff_test(test_sequence)
add_diff_test(test_line_optimization)
add_diff_test(test_line_boundary_scoring)
add_diff_test(test_char_level)
add_diff_test(test_dp_algorithm)
add_diff_test(test_char_boundary_categories)
add_diff_test(test_range_mapping)
add_diff_test(test_compute_diff)
add_diff_test(test_render_plan)

# Print configuration
message(STATUS "===========================================")
message(STATUS "  diff_core Configuration")
message(STATUS "===========================================")
message(STATUS "  Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  Platform: ${CMAKE_SYSTEM_NAME}")
message(STATUS "  C Compiler: ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}")
if(USE_BUNDLED_UTF8PROC)
message(STATUS "  utf8proc: bundled (vendor/utf8proc.c)")
else()
message(STATUS "  utf8proc: ${UTF8PROC_LIBRARY}")
endif()
message(STATUS "===========================================")

# Generate standalone build scripts for users without CMake
message(STATUS "Generating standalone build scripts...")

# Determine script output directory (repository root)
set(SCRIPT_OUTPUT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/..)

# Generate build.sh for Unix/Linux/macOS
file(WRITE ${SCRIPT_OUTPUT_DIR}/build.sh
"#!/usr/bin/env bash
# Auto-generated by CMake - DO NOT EDIT MANUALLY
# This script allows building without CMake installed

set -e
cd \"\$(dirname \"\$0\")/c-diff-core\"

echo \"Building diff_core (standalone mode)...\"
echo \"Compiler: ${CMAKE_C_COMPILER}\"
echo \"Platform: ${CMAKE_SYSTEM_NAME}\"

# Compiler and flags from CMake configuration
CC=\"${CMAKE_C_COMPILER}\"
CFLAGS=\"${CMAKE_C_FLAGS} ${CMAKE_C_FLAGS_RELEASE} -Iinclude -Ivendor -fPIC\"
LDFLAGS=\"-shared -lm\"

# Detect platform for library extension
if [[ \"\$OSTYPE\" == \"darwin\"* ]]; then
    LIB_EXT=\"dylib\"
elif [[ \"\$OSTYPE\" == \"linux-gnu\"* ]]; then
    LIB_EXT=\"so\"
else
    LIB_EXT=\"so\"
fi

# Source files (including bundled utf8proc)
SOURCES=\"\\
src/diff_api.c \\
src/render_plan.c \\
default_lines_diff_computer.c \\
src/char_level.c \\
src/line_level.c \\
src/myers.c \\
src/optimize.c \\
src/sequence.c \\
src/range_mapping.c \\
src/string_hash_map.c \\
src/utils.c \\
src/print_utils.c \\
src/utf8_utils.c \\
vendor/utf8proc.c\"

# Build
mkdir -p build
echo \"Compiling...\"
\$CC \$CFLAGS \$LDFLAGS -o libdiff_core.\$LIB_EXT \$SOURCES

echo \"Installing to plugin root...\"
cp libdiff_core.\$LIB_EXT ../libdiff_core.\$LIB_EXT

echo \"✓ Build successful: libdiff_core.\$LIB_EXT\"
cd ..
")

# Make build.sh executable
file(CHMOD ${SCRIPT_OUTPUT_DIR}/build.sh
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                GROUP_READ GROUP_EXECUTE
                WORLD_READ WORLD_EXECUTE)

# Generate build.cmd for Windows
file(WRITE ${SCRIPT_OUTPUT_DIR}/build.cmd
"@echo off
REM Auto-generated by CMake - DO NOT EDIT MANUALLY
REM This script allows building without CMake installed
REM Auto-detects compiler: MSVC, Clang, MinGW GCC

setlocal enabledelayedexpansion
cd /d \"%~dp0\\c-diff-core\"

echo Building diff_core (standalone mode)...
echo Platform: Windows

REM Source files (including bundled utf8proc)
set SOURCES=^
src\\diff_api.c ^
src\\render_plan.c ^
default_lines_diff_computer.c ^
src\\char_level.c ^
src\\line_level.c ^
src\\myers.c ^
src\\optimize.c ^
src\\sequence.c ^
src\\range_mapping.c ^
src\\string_hash_map.c ^
src\\utils.c ^
src\\print_utils.c ^
src\\utf8_utils.c ^
vendor\\utf8proc.c

REM Auto-detect compiler
set COMPILER=unknown

where cl.exe >nul 2>&1
if !errorlevel! == 0 (
    set COMPILER=msvc
    goto :build_msvc
)

where clang.exe >nul 2>&1
if !errorlevel! == 0 (
    set COMPILER=clang
    goto :build_clang
)

where gcc.exe >nul 2>&1
if !errorlevel! == 0 (
    set COMPILER=gcc
    goto :build_gcc
)

echo Error: No C compiler found!
echo Please install one of: Visual Studio (MSVC), Clang, MinGW-w64
cd ..
exit /b 1

:build_msvc
echo Using MSVC compiler...
cl.exe /LD /O2 /W3 /std:c11 /Iinclude /Ivendor /Fe:libdiff_core.dll %SOURCES% /link /DLL
goto :build_done

:build_clang
echo Using Clang compiler...
clang.exe -shared -Wall -Wextra -std=c11 -O2 -Iinclude -Ivendor -o libdiff_core.dll %SOURCES%
goto :build_done

:build_gcc
echo Using MinGW GCC compiler...
gcc.exe -shared -Wall -Wextra -std=c11 -O2 -Iinclude -Ivendor -o libdiff_core.dll %SOURCES%
goto :build_done

:build_done
if !errorlevel! neq 0 (
    echo Build failed!
    cd ..
    exit /b 1
)

echo Installing to plugin root...
copy /Y libdiff_core.dll ..\\libdiff_core.dll >nul

echo.
echo ✓ Build successful: libdiff_core.dll
cd ..
endlocal
")

message(STATUS "✓ Generated: ../build.sh")
message(STATUS "✓ Generated: ../build.cmd")
message(STATUS "  Users can now build without CMake using these scripts at repository root")

