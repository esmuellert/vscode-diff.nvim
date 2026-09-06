# Attribution

This project includes code from or is derived from the following open source projects. We are grateful to the authors and contributors of these projects.

---

## Bundled Dependencies

### utf8proc

**License**: MIT License
**Copyright**: Copyright (c) 2014-2021 Steven G. Johnson, Jiahao Chen, Tony Kelman, Jonas Fonseca, and other contributors
**Source**: https://github.com/JuliaStrings/utf8proc
**Location**: `libvscode-diff/vendor/`
**Purpose**: UTF-8 Unicode string processing

Full license text: [libvscode-diff/vendor/utf8proc_LICENSE.md](libvscode-diff/vendor/utf8proc_LICENSE.md)

---

## Derivative Works

### Microsoft Visual Studio Code

**License**: MIT License
**Copyright**: Copyright (c) Microsoft Corporation
**Source**: https://github.com/microsoft/vscode
**Description**: The diff computation algorithm in this project is a C port of VSCode's `defaultLinesDiffComputer` implementation. The algorithm, data structures, and optimization heuristics are derived from VSCode's TypeScript source code.

**Key Components Ported**:
- Myers diff algorithm (`src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/myersDiffAlgorithm.ts`)
- Dynamic Programming algorithm (`src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/dynamicProgrammingDiffing.ts`)
- Line-level optimization heuristics (`src/vs/editor/common/diff/defaultLinesDiffComputer/heuristicSequenceOptimizations.ts`)
- Character-level refinement (`src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts`)
- Range mapping data structures (`src/vs/editor/common/diff/rangeMapping.ts`)

**VSCode License**: MIT License (see [official license](https://github.com/microsoft/vscode/blob/main/LICENSE.txt))

```
MIT License

Copyright (c) Microsoft Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## External Dependencies

The following dependencies are not bundled but are required for full functionality:

### nui.nvim

**License**: MIT License
**Author**: Munif Tanjim
**Source**: https://github.com/MunifTanjim/nui.nvim
**Purpose**: UI components for file explorer

---

## Architectural Inspiration

The following projects inspired architectural decisions but no code was copied:

### vim-fugitive

**Author**: Tim Pope
**Source**: https://github.com/tpope/vim-fugitive
**Inspiration**: The virtual file URL scheme (`codediff://`) is inspired by vim-fugitive's `fugitive://` pattern for creating virtual buffers that represent git objects.

### gitsigns.nvim & diffview.nvim

**Sources**:
- https://github.com/lewis6991/gitsigns.nvim
- https://github.com/sindrets/diffview.nvim

**Inspiration**: Async git integration patterns and best practices for Neovim git plugins.

---

## Documentation Assets

Colorschemes used in documentation screenshots:

### Tokyo Night

**Author**: folke
**License**: Apache License 2.0
**Source**: https://github.com/folke/tokyonight.nvim
**Usage**: Hero image (Tokyo Night Moon variant)

### Dawnfox

**Author**: EdenEast
**License**: MIT License
**Source**: https://github.com/EdenEast/nightfox.nvim
**Usage**: Highlight groups visual example (Dawnfox Light variant)

### Catppuccin

**Author**: Catppuccin Community
**License**: MIT License
**Source**: https://github.com/catppuccin/nvim
**Usage**: Highlight groups visual example (Mocha variant)

### Kanagawa

**Author**: rebelot
**License**: MIT License
**Source**: https://github.com/rebelot/kanagawa.nvim
**Usage**: Highlight groups visual example (Lotus variant)

---

## Acknowledgments

We would like to thank:

- **Microsoft Corporation** and the VSCode team for creating and open-sourcing an excellent diff algorithm implementation
- **The Neovim contributors** for the editor and plugin infrastructure
- **The JuliaStrings project** and utf8proc contributors for providing a robust Unicode processing library
- **Tim Pope** (vim-fugitive) for pioneering the virtual file URL pattern
- **The Neovim community** for creating the plugin ecosystem and supporting libraries
- **Colorscheme authors** (folke, EdenEast, Catppuccin Community, rebelot) for their beautiful themes used in our documentation
- All contributors to the dependencies and inspirations listed above

---

*This project is distributed under the MIT License. See LICENSE file for details.*
