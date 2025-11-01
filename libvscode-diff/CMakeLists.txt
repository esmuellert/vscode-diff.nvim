cmake_minimum_required(VERSION 3.15)

# Read version from VERSION file (single source of truth)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../VERSION" PROJECT_VERSION)
string(STRIP "${PROJECT_VERSION}" PROJECT_VERSION)

project(libvscode-diff VERSION ${PROJECT_VERSION} LANGUAGES C)

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
add_library(vscode_diff SHARED ${DIFF_CORE_SOURCES})

target_include_directories(vscode_diff
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        $<$<BOOL:${USE_BUNDLED_UTF8PROC}>:${UTF8PROC_INCLUDE}>
)

if(USE_BUNDLED_UTF8PROC)
    # Using bundled utf8proc - no external linking needed
    target_link_libraries(vscode_diff PRIVATE m)
else()
    # Using system utf8proc
    target_link_libraries(vscode_diff PRIVATE ${UTF8PROC_LIBRARY})
endif()

# Platform-specific library naming
if(WIN32)
    set_target_properties(vscode_diff PROPERTIES OUTPUT_NAME "vscode_diff")
    set_target_properties(vscode_diff PROPERTIES SUFFIX ".dll")
elseif(APPLE)
    set_target_properties(vscode_diff PROPERTIES OUTPUT_NAME "vscode_diff")
    set_target_properties(vscode_diff PROPERTIES SUFFIX ".dylib")
else()
    set_target_properties(vscode_diff PROPERTIES OUTPUT_NAME "vscode_diff")
    set_target_properties(vscode_diff PROPERTIES SUFFIX ".so")
endif()

# Install to parent directory (for Lua FFI)
set(INSTALL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/..)
install(TARGETS vscode_diff
    LIBRARY DESTINATION ${INSTALL_DIR}
    RUNTIME DESTINATION ${INSTALL_DIR}
)

# Custom install target that copies immediately
add_custom_command(TARGET vscode_diff POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:vscode_diff>
        ${INSTALL_DIR}/libvscode_diff$<TARGET_FILE_SUFFIX:vscode_diff>
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
message(STATUS "  vscode_diff Configuration")
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

# Generate build.sh for Unix/Linux/macOS using configure_file
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/build.sh.in
    ${SCRIPT_OUTPUT_DIR}/build.sh
    @ONLY
)

# Make build.sh executable
file(CHMOD ${SCRIPT_OUTPUT_DIR}/build.sh
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                GROUP_READ GROUP_EXECUTE
                WORLD_READ WORLD_EXECUTE)

# Generate build.cmd for Windows using configure_file
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/build.cmd.in
    ${SCRIPT_OUTPUT_DIR}/build.cmd
    @ONLY
)

message(STATUS "✓ Generated: ../build.sh")
message(STATUS "✓ Generated: ../build.cmd")
message(STATUS "  Users can now build without CMake using these scripts at repository root")

