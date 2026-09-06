# Development Documentation

**Project**: codediff.nvim — VSCode-quality diff rendering for Neovim
**Started**: October 2024
**Scope**: Development logs, architecture decisions, and parity analysis

This folder documents the full development journey of codediff.nvim, from initial MVP through achieving VSCode algorithm parity and building a full-featured Neovim plugin.

---

## 📖 Reading Paths

### 🟢 The Full Story (chronological)

Read everything in order to understand the complete development journey:

1. [01-origins/mvp-implementation-plan.md](01-origins/mvp-implementation-plan.md) — The original vision and step-by-step plan
2. [01-origins/development-notes.md](01-origins/development-notes.md) — Early architecture, debugging tips, quick reference
3. [01-origins/vscode-parity-assessment.md](01-origins/vscode-parity-assessment.md) — First parity assessment (MVP stage)
4. [02-c-diff-algorithm/](02-c-diff-algorithm/) — The C algorithm journey (Myers, optimization, char-level, parity chase)
5. [03-build-and-platform/](03-build-and-platform/) — Cross-platform builds, installation, tooling
6. [04-lua-features/](04-lua-features/) — Git integration, rendering, explorer, virtual files
7. [05-architecture/](05-architecture/) — Async design, auto-refresh, timeout, refactoring plans

### 🔵 "I want to understand the diff algorithm"

1. [01-origins/mvp-implementation-plan.md](01-origins/mvp-implementation-plan.md) — Data structures and VSCode reference architecture
2. [02-c-diff-algorithm/implementation-plan.md](02-c-diff-algorithm/implementation-plan.md) — Pipeline design for the advanced algorithm
3. [02-c-diff-algorithm/step1-myers-devlog.md](02-c-diff-algorithm/step1-myers-devlog.md) — Myers O(ND) implementation
4. [02-c-diff-algorithm/step2-step3-optimization-devlog.md](02-c-diff-algorithm/step2-step3-optimization-devlog.md) — Line-level heuristics
5. [02-c-diff-algorithm/step4-char-refinement-devlog.md](02-c-diff-algorithm/step4-char-refinement-devlog.md) — Character-level refinement
6. [02-c-diff-algorithm/parity-evaluation-journey.md](02-c-diff-algorithm/parity-evaluation-journey.md) — Chasing exact VSCode parity
7. [02-c-diff-algorithm/utf8-and-vscode-parity.md](02-c-diff-algorithm/utf8-and-vscode-parity.md) — UTF-8/UTF-16 encoding challenges

### 🟡 "I want to understand the Lua plugin"

1. [04-lua-features/git-integration.md](04-lua-features/git-integration.md) — Git revision comparison
2. [04-lua-features/rendering-evolution.md](04-lua-features/rendering-evolution.md) — Filler lines, colors, extmark layering
3. [04-lua-features/virtual-file-implementation.md](04-lua-features/virtual-file-implementation.md) — Tree-sitter highlighting via virtual files
4. [04-lua-features/explorer-mode.md](04-lua-features/explorer-mode.md) — File sidebar with git status
5. [05-architecture/auto-refresh-strategy.md](05-architecture/auto-refresh-strategy.md) — How VSCode refreshes diffs
6. [05-architecture/async-diff-architecture.md](05-architecture/async-diff-architecture.md) — Non-blocking diff computation
7. [05-architecture/architecture-refactor-plan.md](05-architecture/architecture-refactor-plan.md) — Module reorganization plan

### 🔴 "I want to build or deploy"

1. [03-build-and-platform/cross-platform-compatibility.md](03-build-and-platform/cross-platform-compatibility.md) — Windows/Linux/macOS portability
2. [03-build-and-platform/header-include-refactoring.md](03-build-and-platform/header-include-refactoring.md) — C include path cleanup
3. [03-build-and-platform/vscode-extraction-tool.md](03-build-and-platform/vscode-extraction-tool.md) — Extract VSCode's diff as reference tool
4. [03-build-and-platform/automatic-installation.md](03-build-and-platform/automatic-installation.md) — Auto-download of pre-built binaries

---

## 📁 Directory Structure

```
docs/development/
├── 01-origins/              # The beginning: MVP plan, early notes, first assessment
├── 02-c-diff-algorithm/     # C core algorithm: Myers, optimization, char-level, parity
├── 03-build-and-platform/   # Build system, cross-platform, installation
├── 04-lua-features/         # Lua plugin features: git, rendering, explorer, virtual files
├── 05-architecture/         # Design decisions: async, refresh, timeout, refactoring
└── assets/                  # Images and diagrams
```

---

## 🕐 Timeline

| Date | Milestone |
|------|-----------|
| Oct 2024 | MVP: LCS diff + basic rendering + filler lines |
| Oct 23-25, 2024 | Advanced diff: Myers O(ND), line optimization, char refinement |
| Oct 25-27, 2024 | Parity chase: 3 evaluations, dozens of fixes (DP, hashing, scoring, UTF-8) |
| Oct 28-29, 2025 | VSCode extraction tool, UTF-8/UTF-16 comprehensive fixes |
| Oct 26, 2025 | Cross-platform compatibility (Windows MSVC support) |
| Oct 27, 2025 | Lua integration: git revision diff, rendering improvements |
| Nov 2025 | Virtual files, Tree-sitter highlighting, auto-refresh, timeout fix, installer |
| Nov 12, 2025 | Explorer mode with file sidebar |
| Dec 2025 | Merge tool alignment parity, architecture refactor planning |

---

## Quick Start

```bash
# Build the C library
make

# Run tests
make test
```

