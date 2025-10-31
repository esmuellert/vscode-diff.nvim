cmake_minimum_required(VERSION 3.15)

# Read version from VERSION file (single source of truth)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" PROJECT_VERSION)
string(STRIP "${PROJECT_VERSION}" PROJECT_VERSION)

project(vscode-diff-nvim VERSION ${PROJECT_VERSION})

# This is the root CMakeLists.txt for the Neovim plugin
# It delegates C building to c-diff-core/

# Add C core subdirectory
add_subdirectory(c-diff-core)

message(STATUS "===========================================")
message(STATUS "  vscode-diff.nvim Plugin")
message(STATUS "===========================================")
message(STATUS "  Build the plugin:")
message(STATUS "    cmake -B build")
message(STATUS "    cmake --build build")
message(STATUS "")
message(STATUS "  Run C tests:")
message(STATUS "    cmake --build build --target test")
message(STATUS "    ctest --test-dir build")
message(STATUS "")
message(STATUS "  Run Lua tests:")
message(STATUS "    ./tests/run_tests.sh")
message(STATUS "    make test-lua")
message(STATUS "===========================================")

