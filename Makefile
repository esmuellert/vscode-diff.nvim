# Makefile for vscode-diff.nvim
# Convenience wrapper around CMake

.PHONY: all build generate-scripts test test-c test-lua clean help

# Default target: build with CMake (generates standalone scripts too)
all: build
	@echo ""
	@echo "✓ Plugin built successfully"
	@echo "  Standalone scripts generated: c-diff-core/build.sh, c-diff-core/build.cmd"
	@echo "  Run 'make test' to run all tests"

# Build using CMake (also generates standalone build scripts)
build:
	@echo "Building with CMake (will generate standalone scripts)..."
	@cmake -B build -S .
	@cmake --build build

# Generate standalone scripts only (doesn't build)
generate-scripts:
	@echo "Generating standalone build scripts..."
	@cmake -B build -S .
	@echo "✓ Generated: c-diff-core/build.sh"
	@echo "✓ Generated: c-diff-core/build.cmd"
	@echo ""
	@echo "Users can now build without CMake:"
	@echo "  ./c-diff-core/build.sh        (Unix/Linux/macOS)"
	@echo "  c-diff-core\\build.cmd         (Windows)"

# Install library (same as build for this plugin)
install: build

# Run all tests (C + Lua)
test: test-c test-lua
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  ✓ ALL TESTS PASSED (C + Lua)                              ║"
	@echo "╚════════════════════════════════════════════════════════════╝"

# Run C unit tests (via CMake/CTest)
test-c: build
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║  Running C Unit Tests (CTest)...                           ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@cd build && ctest --output-on-failure

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
	@rm -rf build
	@rm -f libdiff_core.so libdiff_core.dylib libdiff_core.dll
	@rm -f c-diff-core/libdiff_core.*
	@rm -rf c-diff-core/build
	@echo "✓ Clean complete"

# Show help
help:
	@echo "vscode-diff.nvim - Build System"
	@echo ""
	@echo "Build Commands:"
	@echo "  make                 Build with CMake (generates standalone scripts)"
	@echo "  make generate-scripts Generate build.sh/build.cmd only (no build)"
	@echo ""
	@echo "Test Commands:"
	@echo "  make test            Run all tests (C + Lua)"
	@echo "  make test-c          Run C unit tests only (CTest)"
	@echo "  make test-lua        Run Lua integration tests only"
	@echo ""
	@echo "Other:"
	@echo "  make clean           Remove all build artifacts"
	@echo "  make help            Show this help"
	@echo ""
	@echo "CMake-Generated Standalone Scripts (no CMake needed):"
	@echo "  ./c-diff-core/build.sh        Unix/Linux/macOS"
	@echo "  c-diff-core\\build.cmd         Windows"
	@echo ""
	@echo "Direct CMake Usage:"
	@echo "  cmake -B build"
	@echo "  cmake --build build"
