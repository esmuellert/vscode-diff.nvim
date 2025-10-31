cmake_minimum_required(VERSION 3.15)
project(vscode-diff-nvim VERSION 0.3.0)

# This is the root CMakeLists.txt for the Neovim plugin
# It delegates C building to c-diff-core/

# Add C core subdirectory
add_subdirectory(c-diff-core)

# Lua tests are run via shell script (not part of CMake)
# Use: ./tests/run_tests.sh

# Custom target to run Lua tests
add_custom_target(test-lua
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tests/run_tests.sh
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Running Lua integration tests"
)

# Custom target to run all tests (C + Lua)
add_custom_target(test-all
    COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target test
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tests/run_tests.sh
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Running all tests (C + Lua)"
)

message(STATUS "===========================================")
message(STATUS "  vscode-diff.nvim Plugin")
message(STATUS "===========================================")
message(STATUS "  Build the plugin:")
message(STATUS "    cmake -B build")
message(STATUS "    cmake --build build")
message(STATUS "")
message(STATUS "  Run tests:")
message(STATUS "    cmake --build build --target test        (C tests only)")
message(STATUS "    cmake --build build --target test-lua    (Lua tests only)")
message(STATUS "    cmake --build build --target test-all    (All tests)")
message(STATUS "===========================================")
