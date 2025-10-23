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
MYERS_SRC = $(SRC_DIR)/myers.c

# Test executables
TEST_MYERS = $(BUILD_DIR)/test_myers

.PHONY: all clean test test-myers

all: $(BUILD_DIR)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Build and run Myers tests
test-myers: $(BUILD_DIR)
	$(CC) $(CFLAGS) $(TEST_DIR)/test_myers.c $(MYERS_SRC) $(UTILS_SRC) -o $(TEST_MYERS)
	@echo ""
	@echo "Running Myers diff tests..."
	@echo ""
	@$(TEST_MYERS)

# Run all tests
test: test-myers

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
