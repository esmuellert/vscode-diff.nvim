# Agent Instructions

## General CLI Agent Behavior Instructions

### Communication Guidelines

1. **Output Messages**: When responding to users, utilize the native chat output interface. Do not use command-line utilities such as `cat`, `echo`, or `write-host` to display messages in the console. Do not use `cat` to save docs to `/tmp` folder

2. **Code Modifications**: When modifying code, use native patch/diff-based modification tools and APIs. Do not use script-based operations or command-line utilities like `cat`, `sed`, `awk`, or `grep` to perform code edits.

## Path-Specific Instructions

Path-specific instructions are defined in `.github/copilot-instructions.md` files within respective directories.
