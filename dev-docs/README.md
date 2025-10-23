# Development Documentation

**Created**: 2024-10-23

This folder contains development documentation for the vscode-diff.nvim project.

## Documents

### 1. [VSCODE_PARITY_ASSESSMENT.md](./VSCODE_PARITY_ASSESSMENT.md)
**Purpose**: Comprehensive assessment of parity with VSCode's diff editor  
**Key Findings**:
- ✅ Rendering mechanism is at full parity with VSCode
- ⚠️ Diff algorithm uses LCS instead of Myers (functionally equivalent)
- ✅ Visual presentation matches VSCode exactly
- ✅ Filler lines working correctly

### 2. [DEVELOPMENT_NOTES.md](./DEVELOPMENT_NOTES.md)
**Purpose**: Quick reference, architecture notes, and debugging tips  
**Contents**:
- Project status and testing commands
- Architecture and data flow
- VSCode parity analysis
- Debugging tips and common issues
- Performance notes

## Quick Start

```bash
# Run tests
make test

# Run with verbose output
nvim --headless -c "luafile tests/e2e_test.lua" -- -v
```

## Key Files

- **C Core**: `../c-diff-core/diff_core.c`
- **Lua Renderer**: `../lua/vscode-diff/init.lua`  
- **Implementation Spec**: `../VSCODE_DIFF_MVP_IMPLEMENTATION_PLAN.md`
- **Render Plan Spec**: `../docs/RENDER_PLAN.md`

## Status

**MVP**: ✅ **Complete and Ready to Ship**

See [VSCODE_PARITY_ASSESSMENT.md](./VSCODE_PARITY_ASSESSMENT.md) for detailed parity analysis.

