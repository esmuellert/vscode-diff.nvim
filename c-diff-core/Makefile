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
SEQUENCE_SRC = $(SRC_DIR)/sequence.c
MYERS_SRC = $(SRC_DIR)/myers.c
OPTIMIZE_SRC = $(SRC_DIR)/optimize.c
REFINE_SRC = $(SRC_DIR)/refine.c
CHAR_LEVEL_SRC = $(SRC_DIR)/char_level.c

# Test executables
TEST_MYERS = $(BUILD_DIR)/test_myers
TEST_INFRASTRUCTURE = $(BUILD_DIR)/test_infrastructure
TEST_LINE_OPT = $(BUILD_DIR)/test_line_optimization
TEST_REFINE = $(BUILD_DIR)/test_refine
TEST_CHAR_LEVEL = $(BUILD_DIR)/test_char_level
TEST_INTEGRATION = $(BUILD_DIR)/test_integration

.PHONY: all clean test test-myers test-infrastructure test-line-opt test-refine test-char-level test-integration

all: $(BUILD_DIR)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Build and run Myers tests
test-myers: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_myers.c $(MYERS_SRC) $(SEQUENCE_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_MYERS)
	@echo ""
	@echo "Running Myers diff tests..."
	@echo ""
	@$(TEST_MYERS)

# Build and run Infrastructure tests (ISequence, LineSequence, CharSequence)
test-infrastructure: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_infrastructure.c $(MYERS_SRC) $(SEQUENCE_SRC) $(UTILS_SRC) -o $(TEST_INFRASTRUCTURE)
	@echo ""
	@echo "Running Infrastructure tests..."
	@echo ""
	@$(TEST_INFRASTRUCTURE)

# Build and run Line Optimization tests (Step 1+2+3)
test-line-opt: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_line_optimization.c $(MYERS_SRC) $(OPTIMIZE_SRC) $(SEQUENCE_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_LINE_OPT)
	@echo ""
	@echo "Running Line-Level Optimization tests (Steps 1+2+3)..."
	@echo ""
	@$(TEST_LINE_OPT)

# Build and run Refine tests (Step 4 - old implementation)
test-refine: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_refine.c $(REFINE_SRC) $(MYERS_SRC) $(OPTIMIZE_SRC) $(SEQUENCE_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_REFINE)
	@echo ""
	@echo "Running Character Refinement tests (Old implementation)..."
	@echo ""
	@$(TEST_REFINE)

# Build and run Character-Level tests (Step 4 - NEW VSCODE PARITY)
test-char-level: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_char_level.c $(CHAR_LEVEL_SRC) $(MYERS_SRC) $(OPTIMIZE_SRC) $(SEQUENCE_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_CHAR_LEVEL) -lm
	@echo ""
	@echo "Running Character-Level Optimization tests (Step 4 - VSCODE PARITY)..."
	@echo ""
	@$(TEST_CHAR_LEVEL)

# Build and run Integration test (Full Pipeline: Steps 1-4)
test-integration: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_integration.c $(MYERS_SRC) $(OPTIMIZE_SRC) $(REFINE_SRC) $(UTILS_SRC) $(PRINT_UTILS_SRC) -o $(TEST_INTEGRATION)
	@$(TEST_INTEGRATION)

# Run all tests
test: test-myers test-line-opt test-char-level

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
