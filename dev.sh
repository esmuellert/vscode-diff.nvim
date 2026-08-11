#!/usr/bin/env bash
# Launch Neovim with your normal config, but with THIS worktree's copy of
# codediff.nvim taking precedence over any plugin-manager-installed version.
#
# Enables parallel worktree development: run ./dev.sh in different terminals,
# one per worktree — each nvim keeps your full editor experience (colorscheme,
# LSP, keymaps, other plugins) but previews its own copy of the codediff
# plugin source.
#
# Mechanics — --cmd runs BEFORE your init.lua:
#   1. shadafile=NONE avoids two parallel nvims fighting over the shada file.
#   2. prepend.lua puts this worktree first on runtimepath and package.path,
#      so any require("codediff.*") — from your config or from another plugin
#      — resolves to this worktree's Lua rather than your plugin manager's
#      installed copy.
#
# Linux/macOS only for now.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec nvim \
  --cmd "set shadafile=NONE" \
  --cmd "luafile $here/scripts/dev/prepend.lua" \
  "$@"
