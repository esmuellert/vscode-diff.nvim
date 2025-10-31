# Makefile for vscode-diff.nvim
# Convenience wrapper around CMake

.PHONY: all build generate-scripts test test-c test-lua clean help bump-patch bump-minor bump-major version

# Default target: build with CMake (generates standalone scripts too)
all: build
	@echo ""
	@echo "✓ Plugin built successfully"
	@echo "  Standalone scripts generated: libvscode-diff/build.sh, libvscode-diff/build.cmd"
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
	@echo "✓ Generated: libvscode-diff/build.sh"
	@echo "✓ Generated: libvscode-diff/build.cmd"
	@echo ""
	@echo "Users can now build without CMake:"
	@echo "  ./libvscode-diff/build.sh        (Unix/Linux/macOS)"
	@echo "  libvscode-diff\\build.cmd         (Windows)"

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
	@rm -f libvscode_diff.so libvscode_diff.dylib libvscode_diff.dll
	@rm -f libvscode-diff/libvscode_diff.*
	@rm -rf libvscode-diff/build
	@echo "✓ Clean complete"

# Version management
version:
	@cat VERSION

bump-patch:
	@node scripts/bump_version.mjs patch

bump-minor:
	@node scripts/bump_version.mjs minor

bump-major:
	@node scripts/bump_version.mjs major

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
	@echo "Version Management:"
	@echo "  make version         Show current version"
	@echo "  make bump-patch      Bump patch version (0.3.0 → 0.3.1)"
	@echo "  make bump-minor      Bump minor version (0.3.0 → 0.4.0)"
	@echo "  make bump-major      Bump major version (0.3.0 → 1.0.0)"
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
