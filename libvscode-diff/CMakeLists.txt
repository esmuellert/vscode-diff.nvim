cmake_minimum_required(VERSION 3.15)

# Set policies to suppress warnings
if(POLICY CMP0177)
    cmake_policy(SET CMP0177 NEW) # install() DESTINATION paths are normalized
endif()

# Read version from VERSION file (single source of truth)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../VERSION" FULL_VERSION)
string(STRIP "${FULL_VERSION}" FULL_VERSION)

# Extract base version for CMake (handles prerelease like 2.0.0-next.1)
string(REGEX REPLACE "^([0-9]+\\.[0-9]+\\.[0-9]+).*" "\\1" BASE_VERSION "${FULL_VERSION}")

project(libvscode-diff VERSION ${BASE_VERSION} LANGUAGES C)

# Store full version for display/packaging
set(PROJECT_FULL_VERSION "${FULL_VERSION}")

# Generate compile_commands.json for LSP/clangd
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Generate version.h at build time
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/include/version.h.in
    ${CMAKE_CURRENT_BINARY_DIR}/include/version.h
    @ONLY
)

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
if(MSVC)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /W3")
    set(CMAKE_C_FLAGS_DEBUG "/Od /Zi")
    set(CMAKE_C_FLAGS_RELEASE "/O2 /DNDEBUG")
else()
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")
    set(CMAKE_C_FLAGS_DEBUG "-g -O0")
    set(CMAKE_C_FLAGS_RELEASE "-O2 -DNDEBUG")
endif()

# POSIX flags for non-Windows
if(NOT WIN32)
    add_definitions(-D_POSIX_C_SOURCE=200809L)
endif()

# Option to disable OpenMP (for testing or compatibility)
option(ENABLE_OPENMP "Enable OpenMP for parallel character-level diff" ON)

# Find OpenMP for parallelization
if(ENABLE_OPENMP)
    find_package(OpenMP)
endif()

# On macOS, CMake's FindOpenMP doesn't detect Homebrew's libomp
# Try to find it manually if standard detection fails
if(ENABLE_OPENMP AND NOT OpenMP_C_FOUND AND APPLE)
    # Try to find Homebrew's libomp
    execute_process(
        COMMAND brew --prefix libomp
        OUTPUT_VARIABLE HOMEBREW_LIBOMP_PREFIX
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
        RESULT_VARIABLE BREW_RESULT
    )
    
    if(BREW_RESULT EQUAL 0 AND EXISTS "${HOMEBREW_LIBOMP_PREFIX}")
        message(STATUS "Found Homebrew libomp at: ${HOMEBREW_LIBOMP_PREFIX}")
        
        # Set OpenMP flags for Clang on macOS (as a list, not a string)
        set(OpenMP_C_FLAGS "-Xpreprocessor" "-fopenmp")
        set(OpenMP_C_LIB_NAMES "omp")
        set(OpenMP_omp_LIBRARY "${HOMEBREW_LIBOMP_PREFIX}/lib/libomp.dylib")
        set(HOMEBREW_LIBOMP_INCLUDE "${HOMEBREW_LIBOMP_PREFIX}/include")
        
        # Verify the library and header exist
        if(EXISTS "${OpenMP_omp_LIBRARY}" AND EXISTS "${HOMEBREW_LIBOMP_INCLUDE}/omp.h")
            set(OpenMP_C_FOUND TRUE)
            set(HOMEBREW_OPENMP TRUE)
        endif()
    endif()
endif()

if(OpenMP_C_FOUND)
    set(USE_OPENMP TRUE)
    message(STATUS "OpenMP found: Character-level diff will use multi-core parallelization")
else()
    set(USE_OPENMP FALSE)
    message(STATUS "OpenMP not found: Using sequential character-level diff")
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
    default_lines_diff_computer.c
    src/char_level.c
    src/line_level.c
    src/line_matcher.c
    src/myers.c
    src/optimize.c
    src/sequence.c
    src/range_mapping.c
    src/string_hash_map.c
    src/utils.c
    src/print_utils.c
    src/utf8_utils.c
    src/compute_moved_lines.c
)

# Add bundled utf8proc if using it
if(USE_BUNDLED_UTF8PROC)
    list(APPEND DIFF_CORE_SOURCES ${UTF8PROC_SOURCES})
endif()

# Shared library target
if(WIN32 AND MSVC)
    # Use .def file for explicit exports on Windows MSVC
    add_library(vscode_diff SHARED ${DIFF_CORE_SOURCES} libvscode_diff.def)
else()
    add_library(vscode_diff SHARED ${DIFF_CORE_SOURCES})
endif()

target_include_directories(vscode_diff
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        $<$<BOOL:${USE_BUNDLED_UTF8PROC}>:${UTF8PROC_INCLUDE}>
)

# Define UTF8PROC_STATIC when using bundled utf8proc
if(USE_BUNDLED_UTF8PROC)
    target_compile_definitions(vscode_diff PRIVATE UTF8PROC_STATIC)
endif()

# Define BUILDING_DLL for Windows DLL export
if(WIN32)
    target_compile_definitions(vscode_diff PRIVATE BUILDING_DLL)
endif()

# Enable OpenMP if available
if(USE_OPENMP)
    target_compile_definitions(vscode_diff PRIVATE USE_OPENMP)
    
    if(HOMEBREW_OPENMP)
        # Homebrew OpenMP on macOS - manual configuration
        target_compile_options(vscode_diff PRIVATE ${OpenMP_C_FLAGS})
        target_include_directories(vscode_diff PRIVATE ${HOMEBREW_LIBOMP_INCLUDE})
        target_link_libraries(vscode_diff PRIVATE ${OpenMP_omp_LIBRARY})
    else()
        # Standard OpenMP via find_package
        target_link_libraries(vscode_diff PRIVATE OpenMP::OpenMP_C)
        
        # Set RPATH to find bundled libgomp.so.1 in the same directory (Linux)
        if(UNIX AND NOT APPLE)
            set_target_properties(vscode_diff PROPERTIES
                BUILD_WITH_INSTALL_RPATH TRUE
                INSTALL_RPATH "$ORIGIN"
            )
        endif()
    endif()
endif()

if(USE_BUNDLED_UTF8PROC)
    # Using bundled utf8proc - no external linking needed
    if(NOT WIN32)
        target_link_libraries(vscode_diff PRIVATE m)
    endif()
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
# Use copy_if_different to avoid unnecessary timestamp updates
if(WIN32)
    # Windows: Copy with error suppression if file is locked
    add_custom_command(TARGET vscode_diff POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo "Installing library to plugin root..."
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:vscode_diff>
            ${INSTALL_DIR}/libvscode_diff$<TARGET_FILE_SUFFIX:vscode_diff>
            || (exit 0)
        COMMENT "Installing library (skips if unchanged or locked)"
    )
else()
    # Unix: Use copy_if_different (no locking issues)
    add_custom_command(TARGET vscode_diff POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:vscode_diff>
            ${INSTALL_DIR}/libvscode_diff$<TARGET_FILE_SUFFIX:vscode_diff>
        COMMENT "Installing library to plugin root"
    )
endif()

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
    src/line_matcher.c
    src/char_level.c
    src/range_mapping.c
    src/utf8_utils.c
    src/compute_moved_lines.c
    default_lines_diff_computer.c
)

# Add bundled utf8proc to tests if using it
if(USE_BUNDLED_UTF8PROC)
    list(APPEND TEST_COMMON_SOURCES ${UTF8PROC_SOURCES})
endif()

# Helper function to add tests
# Note: Tests compile sources directly because they test internal functions
# not exported in the DLL. This causes duplicate compilation but ensures
# thorough testing of internal APIs.
function(add_diff_test test_name)
    add_executable(${test_name} tests/${test_name}.c ${TEST_COMMON_SOURCES})
    target_include_directories(${test_name} PRIVATE 
        include
        ${CMAKE_CURRENT_BINARY_DIR}/include
    )
    
    # Define BUILDING_DLL for tests to avoid DLL linkage warnings
    # Tests compile sources directly, treating them as if building a library
    if(WIN32)
        target_compile_definitions(${test_name} PRIVATE BUILDING_DLL)
    endif()
    
    if(USE_BUNDLED_UTF8PROC)
        target_include_directories(${test_name} PRIVATE ${UTF8PROC_INCLUDE})
        target_compile_definitions(${test_name} PRIVATE UTF8PROC_STATIC)
        if(NOT WIN32)
            target_link_libraries(${test_name} PRIVATE m)
        endif()
    else()
        if(WIN32)
            target_link_libraries(${test_name} PRIVATE ${UTF8PROC_LIBRARY})
        else()
            target_link_libraries(${test_name} PRIVATE ${UTF8PROC_LIBRARY} m)
        endif()
    endif()
    
    # Enable OpenMP for tests too
    if(USE_OPENMP)
        target_compile_definitions(${test_name} PRIVATE USE_OPENMP)
        if(HOMEBREW_OPENMP)
            target_compile_options(${test_name} PRIVATE ${OpenMP_C_FLAGS})
            target_include_directories(${test_name} PRIVATE ${HOMEBREW_LIBOMP_INCLUDE})
            target_link_libraries(${test_name} PRIVATE ${OpenMP_omp_LIBRARY})
        else()
            target_link_libraries(${test_name} PRIVATE OpenMP::OpenMP_C)
        endif()
    endif()
    
    add_test(NAME ${test_name} COMMAND ${test_name})
endfunction()

# Add all tests
add_diff_test(test_myers)
add_diff_test(test_sequence)
add_diff_test(test_line_optimization)
add_diff_test(test_line_boundary_scoring)
add_diff_test(test_line_matcher)
add_diff_test(test_char_level)
add_diff_test(test_dp_algorithm)
add_diff_test(test_char_boundary_categories)
add_diff_test(test_range_mapping)
add_diff_test(test_compute_diff)
add_diff_test(test_memory_leak)

# ============================================================================
# Valgrind Memory Leak Test
# ============================================================================

# Find Valgrind (optional, won't fail if not found)
find_program(VALGRIND_EXECUTABLE valgrind)

if(VALGRIND_EXECUTABLE)
    # Add Valgrind test
    add_test(
        NAME test_memory_leak_valgrind
        COMMAND ${VALGRIND_EXECUTABLE}
            --leak-check=full
            --show-leak-kinds=definite,possible
            --errors-for-leak-kinds=definite
            --error-exitcode=1
            --track-origins=yes
            $<TARGET_FILE:test_memory_leak>
    )
    
    message(STATUS "Valgrind found: Memory leak testing enabled")
    message(STATUS "  Run: make test                    (normal tests)")
    message(STATUS "  Run: ctest -R valgrind -V         (valgrind test with output)")
else()
    message(STATUS "Valgrind not found: Memory leak test will run without valgrind")
    message(STATUS "  Install: sudo apt-get install valgrind")
endif()

# ============================================================================
# Diff Tool (command-line utility for testing)
# ============================================================================

add_executable(diff diff_tool.c ${DIFF_CORE_SOURCES})
target_include_directories(diff PRIVATE 
    include
    ${CMAKE_CURRENT_BINARY_DIR}/include
)

# Define BUILDING_DLL for diff CLI to avoid DLL linkage warnings
# CLI compiles sources directly, treating them as if building a library
if(WIN32)
    target_compile_definitions(diff PRIVATE BUILDING_DLL)
endif()

if(USE_BUNDLED_UTF8PROC)
    target_include_directories(diff PRIVATE ${UTF8PROC_INCLUDE})
    target_compile_definitions(diff PRIVATE UTF8PROC_STATIC)
    if(NOT WIN32)
        target_link_libraries(diff PRIVATE m)
    endif()
else()
    if(WIN32)
        target_link_libraries(diff PRIVATE ${UTF8PROC_LIBRARY})
    else()
        target_link_libraries(diff PRIVATE ${UTF8PROC_LIBRARY} m)
    endif()
endif()

# Enable OpenMP for diff tool
if(USE_OPENMP)
    target_compile_definitions(diff PRIVATE USE_OPENMP)
    if(HOMEBREW_OPENMP)
        target_compile_options(diff PRIVATE ${OpenMP_C_FLAGS})
        target_include_directories(diff PRIVATE ${HOMEBREW_LIBOMP_INCLUDE})
        target_link_libraries(diff PRIVATE ${OpenMP_omp_LIBRARY})
    else()
        target_link_libraries(diff PRIVATE OpenMP::OpenMP_C)
    endif()
endif()

# Copy diff tool to plugin root for easy access (similar to library)
# Use copy_if_different to avoid unnecessary timestamp updates
add_custom_command(TARGET diff POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        $<TARGET_FILE:diff>
        ${INSTALL_DIR}/$<TARGET_FILE_NAME:diff>
    COMMENT "Installing diff CLI tool to plugin root"
)

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
if(USE_OPENMP)
message(STATUS "  OpenMP: enabled (multi-core char diff)")
else()
message(STATUS "  OpenMP: disabled (sequential char diff)")
endif()
message(STATUS "===========================================")

# Generate standalone build scripts for users without CMake
message(STATUS "Generating standalone build scripts...")

# Determine script output directory (repository root)
set(SCRIPT_OUTPUT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/..)

# Generate build.sh for Unix/Linux/macOS (with LF line endings)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/build.sh.in
    ${SCRIPT_OUTPUT_DIR}/build.sh
    @ONLY
    NEWLINE_STYLE LF
)

# Make build.sh executable on Unix-like systems
if(UNIX)
    # Use execute_process instead of file(CHMOD) for CMake 3.15 compatibility
    execute_process(COMMAND chmod +x ${SCRIPT_OUTPUT_DIR}/build.sh)
endif()
message(STATUS "✓ Generated: ../build.sh")

# Generate build.cmd for Windows (with CRLF line endings)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/build.cmd.in
    ${SCRIPT_OUTPUT_DIR}/build.cmd
    @ONLY
    NEWLINE_STYLE CRLF
)
message(STATUS "✓ Generated: ../build.cmd")

message(STATUS "  Users can now build without CMake using these scripts at repository root")

