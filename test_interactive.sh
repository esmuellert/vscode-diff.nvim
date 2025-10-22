#!/bin/bash
# Interactive test script for vscode-diff.nvim
# This script launches Neovim with the plugin loaded and test files open

cd "$(dirname "$0")"

echo "=== vscode-diff.nvim Interactive Test ==="
echo ""
echo "This will open Neovim with a side-by-side diff of test files."
echo "The plugin should show:"
echo "  - Light backgrounds on modified lines"
echo "  - Darker highlights on changed characters"
echo "  - Line alignment with virtual filler lines"
echo ""
echo "Press Enter to continue..."
read

# Launch Neovim with the plugin and test files
nvim -c "set rtp+=." \
     -c "runtime plugin/vscode-diff.lua" \
     -c "VscodeDiff tests/fixtures/file_a.txt tests/fixtures/file_b.txt"

echo ""
echo "Test complete!"
