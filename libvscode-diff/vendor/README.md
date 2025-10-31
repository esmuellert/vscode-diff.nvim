# Bundled Third-Party Libraries

This directory contains vendored (bundled) third-party libraries to eliminate external dependencies.

## utf8proc

**Version:** Latest from master (downloaded 2024-10-31)  
**License:** MIT/Unicode (see utf8proc_LICENSE.md)  
**Source:** https://github.com/JuliaStrings/utf8proc

### What is utf8proc?

A small, clean C library for processing UTF-8 Unicode data. We use it for:
- Converting UTF-8 byte positions to UTF-16 code unit positions
- Matching VSCode's diff behavior (JavaScript uses UTF-16 indexing)
- Handling multi-byte characters correctly (emoji, Chinese, etc.)

### Why bundled?

- **Zero external dependencies** - Users don't need to install anything
- **Windows MSVC compatibility** - utf8proc not available by default
- **Reproducible builds** - Same version everywhere
- **Industry standard** - Like SQLite, stb_image, miniz, etc.

### Files

- `utf8proc.h` - Header file
- `utf8proc.c` - Implementation
- `utf8proc_data.c` - Unicode data tables (included by utf8proc.c)
- `utf8proc_LICENSE.md` - MIT license

### Updating

To update to the latest version:

```bash
cd c-diff-core/vendor
curl -O https://raw.githubusercontent.com/JuliaStrings/utf8proc/master/utf8proc.h
curl -O https://raw.githubusercontent.com/JuliaStrings/utf8proc/master/utf8proc.c
curl -O https://raw.githubusercontent.com/JuliaStrings/utf8proc/master/utf8proc_data.c
curl -O https://raw.githubusercontent.com/JuliaStrings/utf8proc/master/LICENSE.md
mv LICENSE.md utf8proc_LICENSE.md
```

## License Compliance

All bundled libraries are under permissive licenses (MIT, BSD, etc.) compatible with this project.
See individual LICENSE files for details.
