# Detect OS
UNAME_S := $(shell uname -s)

# Compiler settings
CC = gcc
CFLAGS = -Wall -Wextra -O2 -fPIC -std=c11
LDFLAGS = -shared

# Output
ifeq ($(UNAME_S),Linux)
    TARGET = libdiff_core.so
else ifeq ($(UNAME_S),Darwin)
    TARGET = libdiff_core.dylib
else
    TARGET = diff_core.dll
endif

# Source files
SRC = c-diff-core/diff_core.c
OBJ = $(SRC:.c=.o)

# Build targets
all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Build directory for C tests
c-diff-core/build:
	@mkdir -p c-diff-core/build

# C Test Targets
TEST_CFLAGS = -Wall -Wextra -std=c11 -O2 -g -Iinclude
TEST_SOURCES = src/myers.c src/optimize.c src/sequence.c src/utils.c src/print_utils.c src/string_hash_map.c

# Individual test targets
test-myers: c-diff-core/build
	@echo "Running Myers tests..."
	@cd c-diff-core && $(CC) $(TEST_CFLAGS) tests/test_myers.c $(TEST_SOURCES) -o build/test_myers && ./build/test_myers

test-line-opt: c-diff-core/build
	@echo "Running Line Optimization tests (Steps 1+2+3)..."
	@cd c-diff-core && $(CC) $(TEST_CFLAGS) tests/test_line_optimization.c $(TEST_SOURCES) -o build/test_line_opt && ./build/test_line_opt

test-sequence: c-diff-core/build
	@echo "Running Sequence tests (Hash table, ISequence)..."
	@cd c-diff-core && $(CC) $(TEST_CFLAGS) tests/test_sequence.c $(TEST_SOURCES) -o build/test_sequence && ./build/test_sequence

# Build and run all C unit tests
test_c: test-myers test-line-opt test-sequence
	@echo ""
	@echo "================================================"
	@echo "  ALL C UNIT TESTS PASSED ✓"
	@echo "================================================"

# Run C unit tests only (alias)
test-c: test_c

# Run Lua unit tests only
test-unit:
	@./tests/unit/run_all.sh

# Run E2E tests only
test-e2e:
	@./tests/e2e/run_all.sh

# Run E2E tests with verbose output
test-e2e-verbose:
	@./tests/e2e/run_all.sh -v

# Run all tests (C unit + Lua unit + E2E)
test: test_c
	@./tests/run_all.sh

# Run all tests with verbose output
test-verbose: test_c
	@./tests/run_all.sh -v

clean:
	rm -f $(OBJ) $(TARGET) c-diff-core/test_diff_core
	rm -rf c-diff-core/build

.PHONY: all test test-c test-unit test-e2e test-e2e-verbose test-verbose clean test_c test-myers test-line-opt test-sequence
