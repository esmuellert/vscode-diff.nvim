# Makefile for c-diff-core
CC = gcc
CFLAGS = -Wall -Wextra -std=c11 -O2 -g -Iinclude
LDFLAGS = 

# Directories
SRC_DIR = src
TEST_DIR = tests
INC_DIR = include
BUILD_DIR = build

# Source files
UTILS_SRC = $(SRC_DIR)/utils.c
PRINT_UTILS_SRC = $(SRC_DIR)/print_utils.c
MYERS_SRC = $(SRC_DIR)/myers.c
OPTIMIZE_SRC = $(SRC_DIR)/optimize.c
REFINE_SRC = $(SRC_DIR)/refine.c

# Test executables
TEST_MYERS = $(BUILD_DIR)/test_myers
TEST_OPTIMIZE = $(BUILD_DIR)/test_optimize
TEST_REFINE = $(BUILD_DIR)/test_refine
TEST_INTEGRATION = $(BUILD_DIR)/test_integration

.PHONY: all clean test test-myers test-optimize test-refine test-integration

all: $(BUILD_DIR)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Build and run Myers tests
test-myers: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_myers.c $(MYERS_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_MYERS)
	@echo ""
	@echo "Running Myers diff tests..."
	@echo ""
	@$(TEST_MYERS)

# Build and run Optimize tests (Step 2 & 3)
test-optimize: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_optimize.c $(OPTIMIZE_SRC) $(PRINT_UTILS_SRC) -o $(TEST_OPTIMIZE)
	@echo ""
	@echo "Running Optimize diff tests (Step 2 & 3)..."
	@echo ""
	@$(TEST_OPTIMIZE)

# Build and run Refine tests (Step 4)
test-refine: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_refine.c $(REFINE_SRC) $(MYERS_SRC) $(OPTIMIZE_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_REFINE)
	@echo ""
	@echo "Running Character Refinement tests (Step 4)..."
	@echo ""
	@$(TEST_REFINE)

# Build and run Integration test (Full Pipeline: Steps 1-4)
test-integration: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_integration.c $(MYERS_SRC) $(OPTIMIZE_SRC) $(REFINE_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_INTEGRATION)
	@$(TEST_INTEGRATION)

# Run all tests
test: test-myers test-optimize test-refine test-integration

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
