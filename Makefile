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

# Build and run C unit tests
test_c:
	@cd c-diff-core && $(CC) $(CFLAGS) -o test_diff_core test_diff_core.c diff_core.c && ./test_diff_core
	@rm -f c-diff-core/test_diff_core

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

.PHONY: all test test-c test-unit test-e2e test-e2e-verbose test-verbose clean test_c
