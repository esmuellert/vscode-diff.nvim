cmake_minimum_required(VERSION 3.15)
project(vscode-diff-nvim VERSION 0.3.0)

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

