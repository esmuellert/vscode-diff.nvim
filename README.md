# vscode-diff.nvim

A Neovim plugin that provides VSCode-style inline diff rendering with two-tier highlighting.

## Features

- **Two-tier highlighting system**:
  - Light backgrounds for entire modified lines (green for insertions, red for deletions)
  - Deep/dark character-level highlights showing exact changes within lines
- **Side-by-side diff view** with synchronized scrolling
- **Fast C-based diff computation** using FFI
- **Read-only buffers** to prevent accidental edits
- **Aligned line rendering** with virtual filler lines

## Installation

### Prerequisites

- Neovim >= 0.7.0 (for Lua FFI support)
- GCC or compatible C compiler
- Make

### Using lazy.nvim

```lua
{
  dir = "~/.local/share/nvim/vscode-diff.nvim",  -- Update this path
  build = "make clean && make",
  config = function()
    require("vscode-diff.config").setup({
      -- Optional configuration
    })
  end,
}
```

### Manual Installation

1. Clone the repository:
```bash
git clone <repo-url> ~/.local/share/nvim/vscode-diff.nvim
cd ~/.local/share/nvim/vscode-diff.nvim
```

2. Build the C module:
```bash
make clean && make
```

3. Add to your Neovim runtime path in `init.lua`:
```lua
vim.opt.rtp:append("~/.local/share/nvim/vscode-diff.nvim")
```

## Usage

### Basic Command

Compare two files side-by-side:

```vim
:VscodeDiff file_a.txt file_b.txt
```

### Lua API

```lua
local diff = require("vscode-diff")
local render = require("vscode-diff.render")

-- Read files
local lines_a = vim.fn.readfile("file_a.txt")
local lines_b = vim.fn.readfile("file_b.txt")

-- Compute diff
local plan = diff.compute_diff(lines_a, lines_b)

-- Render in buffers
render.setup_highlights()
render.render_diff(lines_a, lines_b, plan)
```

## Architecture

### Components

- **C Module** (`c-diff-core/`): Fast diff computation and render plan generation
  - Myers diff algorithm (simplified for MVP)
  - Character-level LCS for highlighting
  - Matches VSCode's `rangeMapping.ts` data structures

- **Lua FFI Layer** (`lua/vscode-diff/init.lua`): Bridge between C and Lua
  - FFI declarations matching C structs
  - Type conversions between C and Lua

- **Render Module** (`lua/vscode-diff/render.lua`): Neovim buffer rendering
  - VSCode-style highlight groups
  - Virtual line insertion for alignment
  - Side-by-side window management

### Highlight Groups

The plugin defines four highlight groups matching VSCode's diff colors:

- `VscodeDiffLineInsert` - Light green background for inserted lines
- `VscodeDiffLineDelete` - Light red background for deleted lines
- `VscodeDiffCharInsert` - Deep/dark green for inserted characters (THE "DEEPER COLOR")
- `VscodeDiffCharDelete` - Deep/dark red for deleted characters (THE "DEEPER COLOR")

You can customize these in your config:

```lua
vim.api.nvim_set_hl(0, "VscodeDiffCharInsert", { bg = "#2d6d2d" })
```

## Development

### Building

```bash
make clean && make
```

### Testing

Run all tests:
```bash
make test              # Run all tests (C + Lua unit + E2E)
make test-verbose      # Run all tests with verbose C core output
```

Run specific test suites:
```bash
make test-c            # C unit tests only
make test-unit         # Lua unit tests only
make test-e2e          # E2E tests only
make test-e2e-verbose  # E2E tests with verbose output
```

For more details on the test structure, see [`tests/README.md`](tests/README.md).

### Project Structure

```
vscode-diff.nvim/
├── c-diff-core/          # C diff engine
│   ├── diff_core.c       # Implementation
│   ├── diff_core.h       # Header
│   └── test_diff_core.c  # C unit tests
├── lua/vscode-diff/      # Lua modules
│   ├── init.lua          # Main FFI interface
│   ├── config.lua        # Configuration
│   └── render.lua        # Buffer rendering
├── plugin/               # Plugin entry point
│   └── vscode-diff.lua   # Auto-loaded on startup
├── tests/                # Test suite
│   ├── unit/             # Lua unit tests
│   ├── e2e/              # End-to-end tests
│   └── README.md         # Test documentation
├── docs/                 # Production docs
├── dev-docs/             # Development docs
├── Makefile              # Build automation
└── README.md             # This file
```

## Roadmap

### Current Status: MVP Complete ✅

- [x] C-based diff computation
- [x] Two-tier highlighting (line + character level)
- [x] Side-by-side rendering
- [x] Read-only buffers
- [x] Line alignment with filler lines
- [x] Lua FFI bindings
- [x] Basic tests (C, Lua, E2E)

### Future Enhancements

- [ ] Full Myers diff algorithm implementation
- [ ] Advanced character-level LCS
- [ ] Live diff updates on buffer changes
- [ ] Inline diff mode (single buffer)
- [ ] Syntax highlighting preservation
- [ ] Fold support for large diffs
- [ ] Performance optimization for large files
- [ ] Git integration
- [ ] Custom color schemes

## VSCode Reference

This plugin follows VSCode's diff rendering architecture:

- **Data structures**: Based on `src/vs/editor/common/diff/rangeMapping.ts`
- **Decorations**: Based on `src/vs/editor/browser/widget/diffEditor/registrations.contribution.ts`
- **Styling**: Based on `src/vs/editor/browser/widget/diffEditor/style.css`

## License

MIT

## Contributing

Contributions are welcome! Please ensure:
1. C tests pass (`make test`)
2. Lua tests pass
3. Code follows existing style
4. Updates to README if adding features
