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
STRING_HASH_MAP_SRC = $(SRC_DIR)/string_hash_map.c
SEQUENCE_SRC = $(SRC_DIR)/sequence.c
MYERS_SRC = $(SRC_DIR)/myers.c
OPTIMIZE_SRC = $(SRC_DIR)/optimize.c
LINE_LEVEL_SRC = $(SRC_DIR)/line_level.c
CHAR_LEVEL_SRC = $(SRC_DIR)/char_level.c

# Test executables
TEST_MYERS = $(BUILD_DIR)/test_myers
TEST_SEQUENCE = $(BUILD_DIR)/test_sequence
TEST_LINE_OPT = $(BUILD_DIR)/test_line_optimization
TEST_LINE_BOUNDARY = $(BUILD_DIR)/test_line_boundary_scoring
TEST_CHAR_LEVEL = $(BUILD_DIR)/test_char_level
TEST_INTEGRATION = $(BUILD_DIR)/test_integration
TEST_DP = $(BUILD_DIR)/test_dp_algorithm
TEST_CHAR_BOUNDARY = $(BUILD_DIR)/test_char_boundary_categories

.PHONY: all clean test test-myers test-sequence test-line-opt test-line-boundary test-char-level test-integration test-dp test-char-boundary

all: $(BUILD_DIR)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

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
