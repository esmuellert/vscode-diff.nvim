# Makefile for c-diff-core
#
# Targets:
#   make            - Build and install library to plugin root (for Lua FFI)
#   make lib        - Build shared library only (stays in c-diff-core/)
#   make install    - Same as default make (build + install)
#   make test       - Run all tests
#   make clean      - Remove all build artifacts
#
# Individual test targets:
#   make test-myers      - Test Myers diff algorithm
#   make test-sequence   - Test sequence infrastructure
#   make test-line-opt   - Test line-level optimization
#   make test-char-level - Test character-level refinement
#   make test-dp         - Test DP algorithm selection
#
#
CC = gcc
# Base flags for all platforms
CFLAGS_BASE = -Wall -Wextra -std=c11 -O2 -g -Iinclude
CFLAGS_SHARED_BASE = -Wall -Wextra -std=c11 -O2 -g -Iinclude -fPIC

# Platform-specific feature test macros
# _POSIX_C_SOURCE=200809L enables POSIX.1-2008 features (fileno, isatty, etc.)
# Only needed on POSIX systems (Linux, macOS, BSD)
# Windows uses its own _fileno/_isatty and doesn't need this
ifeq ($(OS),Windows_NT)
    # Windows: No POSIX flags needed (_fileno/_isatty from <io.h>)
    CFLAGS = $(CFLAGS_BASE)
    CFLAGS_SHARED = $(CFLAGS_SHARED_BASE)
else
    # POSIX (Linux, macOS, BSD): Need _POSIX_C_SOURCE for fileno()
    CFLAGS = $(CFLAGS_BASE) -D_POSIX_C_SOURCE=200809L
    CFLAGS_SHARED = $(CFLAGS_SHARED_BASE) -D_POSIX_C_SOURCE=200809L
endif

LDFLAGS = 
LDFLAGS_SHARED = -shared

# Directories
SRC_DIR = src
TEST_DIR = tests
INC_DIR = include
BUILD_DIR = build

# Source files
UTILS_SRC = $(SRC_DIR)/utils.c
PRINT_UTILS_SRC = $(SRC_DIR)/print_utils.c
STRING_HASH_MAP_SRC = $(SRC_DIR)/string_hash_map.c
SEQUENCE_SRC = $(SRC_DIR)/sequence.c
MYERS_SRC = $(SRC_DIR)/myers.c
OPTIMIZE_SRC = $(SRC_DIR)/optimize.c
LINE_LEVEL_SRC = $(SRC_DIR)/line_level.c
CHAR_LEVEL_SRC = $(SRC_DIR)/char_level.c
RANGE_MAPPING_SRC = $(SRC_DIR)/range_mapping.c
RENDER_PLAN_SRC = $(SRC_DIR)/render_plan.c
DIFF_API_SRC = $(SRC_DIR)/diff_api.c
DEFAULT_LINES_DIFF_COMPUTER_SRC = default_lines_diff_computer.c

# All source files for shared library
ALL_SRCS = $(DIFF_API_SRC) $(RENDER_PLAN_SRC) $(DEFAULT_LINES_DIFF_COMPUTER_SRC) $(CHAR_LEVEL_SRC) \
           $(LINE_LEVEL_SRC) $(MYERS_SRC) $(OPTIMIZE_SRC) $(SEQUENCE_SRC) $(RANGE_MAPPING_SRC) \
           $(STRING_HASH_MAP_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC)

# Shared library output
SHARED_LIB = libdiff_core.so
ifeq ($(OS),Windows_NT)
    SHARED_LIB = libdiff_core.dll
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Darwin)
        SHARED_LIB = libdiff_core.dylib
    endif
endif

# Test executables
TEST_MYERS = $(BUILD_DIR)/test_myers
TEST_SEQUENCE = $(BUILD_DIR)/test_sequence
TEST_LINE_OPT = $(BUILD_DIR)/test_line_optimization
TEST_LINE_BOUNDARY = $(BUILD_DIR)/test_line_boundary_scoring
TEST_CHAR_LEVEL = $(BUILD_DIR)/test_char_level
TEST_INTEGRATION = $(BUILD_DIR)/test_integration
TEST_DP = $(BUILD_DIR)/test_dp_algorithm
TEST_CHAR_BOUNDARY = $(BUILD_DIR)/test_char_boundary_categories
DIFF_TOOL = $(BUILD_DIR)/diff

.PHONY: all clean test test-myers test-sequence test-line-opt test-line-boundary \
        test-char-level test-integration test-dp test-char-boundary lib install diff-tool

# Default target: build and install for Lua integration
all: install

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Build shared library for Lua integration
lib: $(BUILD_DIR)
	$(CC) $(CFLAGS_SHARED) $(LDFLAGS_SHARED) $(ALL_SRCS) -o $(SHARED_LIB) -lm
	@echo ""
	@echo "✓ Built shared library: $(SHARED_LIB)"
	@echo ""

# Install shared library to plugin root (for Lua FFI)
install: lib
	cp $(SHARED_LIB) ../$(SHARED_LIB)
	@echo ""
	@echo "✓ Installed $(SHARED_LIB) to plugin root"
	@echo "  Lua can now load it via FFI"
	@echo ""

# Build and run Myers tests
test-myers: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_myers.c $(MYERS_SRC) $(SEQUENCE_SRC) $(STRING_HASH_MAP_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_MYERS) -lm
	@echo ""
	@echo "Running Myers diff tests..."
	@echo ""
	@$(TEST_MYERS)

# Build and run Sequence tests (ISequence, LineSequence, CharSequence, Column Translation)
test-sequence: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_sequence.c $(MYERS_SRC) $(SEQUENCE_SRC) $(STRING_HASH_MAP_SRC) $(UTILS_SRC) -o $(TEST_SEQUENCE) -lm
	@echo ""
	@echo "Running Sequence tests (Infrastructure + Column Translation)..."
	@echo ""
	@$(TEST_SEQUENCE)

# Build and run Line Optimization tests (Step 1+2+3)
test-line-opt: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_line_optimization.c $(LINE_LEVEL_SRC) $(MYERS_SRC) $(OPTIMIZE_SRC) $(SEQUENCE_SRC) $(STRING_HASH_MAP_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_LINE_OPT) -lm
	@echo ""
	@echo "Running Line-Level Optimization tests (Steps 1+2+3)..."
	@echo ""
	@$(TEST_LINE_OPT)

# Build and run Line Boundary Scoring test (Proves Myers suboptimal → Optimization fixes)
test-line-boundary: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_line_boundary_scoring.c $(LINE_LEVEL_SRC) $(MYERS_SRC) $(OPTIMIZE_SRC) $(SEQUENCE_SRC) $(STRING_HASH_MAP_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_LINE_BOUNDARY) -lm
	@echo ""
	@echo "Running Boundary Scoring Demonstration (Myers vs Optimized)..."
	@echo ""
	@$(TEST_LINE_BOUNDARY)

# Build and run Character-Level tests (Step 4 - VSCODE PARITY)
test-char-level: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_char_level.c $(CHAR_LEVEL_SRC) $(LINE_LEVEL_SRC) $(MYERS_SRC) $(OPTIMIZE_SRC) $(SEQUENCE_SRC) $(STRING_HASH_MAP_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_CHAR_LEVEL) -lm
	@echo ""
	@echo "Running Character-Level Optimization tests (Step 4 - VSCODE PARITY)..."
	@echo ""
	@$(TEST_CHAR_LEVEL)

# Build and run Integration test (Full Pipeline: Steps 1-4)
test-integration: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_integration.c $(CHAR_LEVEL_SRC) $(LINE_LEVEL_SRC) $(MYERS_SRC) $(OPTIMIZE_SRC) $(SEQUENCE_SRC) $(STRING_HASH_MAP_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_INTEGRATION) -lm
	@$(TEST_INTEGRATION)

# Build and run DP Algorithm tests
test-dp: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_dp_algorithm.c $(MYERS_SRC) $(SEQUENCE_SRC) $(STRING_HASH_MAP_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_DP) -lm
	@echo ""
	@echo "Running DP Algorithm Selection tests..."
	@echo ""
	@$(TEST_DP)

# Build and run Character Boundary Category tests
test-char-boundary: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_char_boundary_categories.c $(SEQUENCE_SRC) $(STRING_HASH_MAP_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_CHAR_BOUNDARY) -lm
	@echo ""
	@echo "Running Character Boundary Category tests..."
	@echo ""
	@$(TEST_CHAR_BOUNDARY)

# Run all tests
test: test-myers test-sequence test-line-opt test-line-boundary test-char-level test-dp test-char-boundary

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(SHARED_LIB)
	rm -f $(DIFF_TOOL)
	rm -f libdiff_core.so libdiff_core.dylib libdiff_core.dll
	rm -f ../libdiff_core.so ../libdiff_core.dylib ../libdiff_core.dll

# Build and run Range Mapping tests
test-range-mapping: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_range_mapping.c $(RANGE_MAPPING_SRC) $(PRINT_UTILS_SRC) -o $(BUILD_DIR)/test_range_mapping -lm
	@echo ""
	@echo "Running Range Mapping Conversion tests..."
	@echo ""
	@$(BUILD_DIR)/test_range_mapping

# Build and run compute_diff tests
test-compute-diff: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_compute_diff.c $(ALL_SRCS) -o $(BUILD_DIR)/test_compute_diff -lm
	@echo ""
	@echo "Running compute_diff() tests..."
	@echo ""
	@$(BUILD_DIR)/test_compute_diff

# Build and run render plan tests
test-render-plan: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_render_plan.c $(ALL_SRCS) -o $(BUILD_DIR)/test_render_plan -lm
	@echo ""
	@echo "Running render plan generation tests..."
	@echo ""
	@$(BUILD_DIR)/test_render_plan

# Build standalone diff tool executable
diff-tool: $(BUILD_DIR)
	$(CC) $(CFLAGS) diff_tool.c $(ALL_SRCS) -o $(DIFF_TOOL) -lm
	@echo ""
	@echo "✓ Built standalone diff tool: $(DIFF_TOOL)"
	@echo "  Usage: $(DIFF_TOOL) <original_file> <modified_file>"
	@echo ""
