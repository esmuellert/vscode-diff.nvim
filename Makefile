# Makefile for vscode-diff.nvim
# Coordinates C core build and Lua integration tests

.PHONY: all build test test-c test-lua clean help

# Default target: build the plugin
all: build
	@echo ""
	@echo "✓ Plugin built successfully"
	@echo "  Run 'make test' to run all tests"

# Build the C core library
build:
	@echo "Building C core library..."
	@cd c-diff-core && $(MAKE)

# Install library (same as build for this plugin)
install: build

# Run all tests (C + Lua)
test: test-c test-lua
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  ✓ ALL TESTS PASSED (C + Lua)                              ║"
	@echo "╚════════════════════════════════════════════════════════════╝"

# Run C unit tests
test-c:
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  Running C Unit Tests...                                   ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@cd c-diff-core && $(MAKE) test

# Run Lua integration tests
test-lua:
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  Running Lua Integration Tests...                          ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@./tests/run_tests.sh

# Clean all build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@cd c-diff-core && $(MAKE) clean
	@rm -f libdiff_core.so libdiff_core.dylib libdiff_core.dll
	@echo "✓ Clean complete"

# Show help
help:
	@echo "vscode-diff.nvim - Makefile targets:"
	@echo ""
	@echo "  make              Build the plugin (C core library)"
	@echo "  make build        Same as 'make'"
	@echo "  make test         Run all tests (C + Lua)"
	@echo "  make test-c       Run C unit tests only"
	@echo "  make test-lua     Run Lua integration tests only"
	@echo "  make clean        Remove all build artifacts"
	@echo "  make help         Show this help message"
	@echo ""
	@echo "Quick start:"
	@echo "  1. make           # Build the plugin"
	@echo "  2. make test      # Run all tests"
