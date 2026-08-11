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

## Vendored Code

### Neovim LSP Semantic Tokens

**License**: Apache License 2.0  
**Copyright**: Copyright Neovim contributors  
**Source**: https://github.com/neovim/neovim  
**Location**: `lua/vscode-diff/render/semantic_tokens.lua` (lines 38-117)  
**Description**: Two helper functions from Neovim's LSP semantic tokens implementation are vendored because there is no public API to process semantic token responses for arbitrary buffers.

**Functions Vendored**:
- `modifiers_from_number()` - Decodes token modifiers from bit field
- `tokens_to_ranges()` - Converts LSP token array to highlight ranges

**Reason for Vendoring**: Neovim's LSP semantic token API is designed for regular buffers only. Virtual/scratch buffers need direct access to the parsing functions, which are not publicly exported.

**Neovim License**: Apache License 2.0 (see [official license](https://github.com/neovim/neovim/blob/master/LICENSE.txt))

```
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   Copyright Neovim contributors.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
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
- **The Neovim contributors** for LSP infrastructure and semantic token support
- **The JuliaStrings project** and utf8proc contributors for providing a robust Unicode processing library
- **Tim Pope** (vim-fugitive) for pioneering the virtual file URL pattern
- **The Neovim community** for creating the plugin ecosystem and supporting libraries
- **Colorscheme authors** (folke, EdenEast, Catppuccin Community, rebelot) for their beautiful themes used in our documentation
- All contributors to the dependencies and inspirations listed above

---

*This project is distributed under the MIT License. See LICENSE file for details.*
