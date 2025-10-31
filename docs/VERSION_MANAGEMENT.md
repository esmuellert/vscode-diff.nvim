# Version Management

This project uses semantic versioning (MAJOR.MINOR.PATCH) with automated version bumping.

## Version File

**Single source of truth:** `VERSION` file at repository root.

All other files read from this:
- `CMakeLists.txt` (root)
- `c-diff-core/CMakeLists.txt`
- Git tags (on release)

## Semantic Versioning

Format: `MAJOR.MINOR.PATCH`

- **PATCH** (0.3.0 → 0.3.1): Bug fixes, backward compatible
- **MINOR** (0.3.0 → 0.4.0): New features, backward compatible  
- **MAJOR** (0.3.0 → 1.0.0): Breaking changes, API changes

## Bumping Version

### Quick Commands

```bash
# Show current version
make version

# Bump patch version (bug fixes)
make bump-patch

# Bump minor version (new features)
make bump-minor

# Bump major version (breaking changes)
make bump-major
```

### Manual Workflow

```bash
# 1. Bump version
make bump-minor

# 2. Commit and tag
git add VERSION
git commit -m "Bump version to $(cat VERSION)"
git tag v$(cat VERSION)

# 3. Push
git push && git push --tags
```

### One-Liner (recommended)

```bash
# After making changes
make bump-minor && \
  git add VERSION && \
  git commit -m "Bump version to $(cat VERSION)" && \
  git tag v$(cat VERSION) && \
  git push && git push --tags
```

## Release Workflow

### 1. Development

```bash
# Make changes
git add .
git commit -m "Add new feature"
```

### 2. Version Bump

Choose the appropriate level:
```bash
make bump-patch   # Bug fixes only
make bump-minor   # New features
make bump-major   # Breaking changes
```

### 3. Release

```bash
# Create release commit and tag
git add VERSION
git commit -m "Release v$(cat VERSION)"
git tag v$(cat VERSION)

# Push to remote
git push origin main
git push origin --tags
```

### 4. Verify

```bash
# Check tags
git tag -l

# Check version
make version
```

## How It Works

### VERSION File

Contains single line with version number:
```
0.3.0
```

### CMake Integration

CMakeLists.txt reads VERSION file:
```cmake
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" PROJECT_VERSION)
string(STRIP "${PROJECT_VERSION}" PROJECT_VERSION)
project(vscode-diff-nvim VERSION ${PROJECT_VERSION})
```

### Bump Script

ES Module script (`scripts/bump_version.mjs`):
1. Reads current version from VERSION file
2. Increments appropriate component
3. Writes new version back
4. Shows next steps

**Requirements:** Node.js (already needed for tests)  
**Style:** ES modules (`.mjs`) - modern JavaScript

## Examples

### Bug Fix Release

```bash
# Fix a bug
git commit -m "Fix column offset calculation"

# Bump patch version (0.3.0 → 0.3.1)
make bump-patch

# Release
git add VERSION
git commit -m "Release v0.3.1"
git tag v0.3.1
git push && git push --tags
```

### Feature Release

```bash
# Add feature
git commit -m "Add async git diff support"

# Bump minor version (0.3.1 → 0.4.0)
make bump-minor

# Release
git add VERSION
git commit -m "Release v0.4.0"
git tag v0.4.0
git push && git push --tags
```

### Breaking Change

```bash
# Make breaking API change
git commit -m "Refactor: Change API structure"

# Bump major version (0.4.0 → 1.0.0)
make bump-major

# Release
git add VERSION
git commit -m "Release v1.0.0"
git tag v1.0.0
git push && git push --tags
```

## Troubleshooting

### Wrong version bumped?

Just edit VERSION file manually:
```bash
echo "0.3.0" > VERSION
git add VERSION
git commit -m "Revert version to 0.3.0"
```

### Tag already exists?

Delete and recreate:
```bash
git tag -d v0.3.0
git tag v0.3.0
git push origin :refs/tags/v0.3.0
git push origin v0.3.0
```

### CMake not picking up new version?

Clean and rebuild:
```bash
make clean
cmake -B build
```

## Best Practices

1. **Always bump before release** - Never release with same version
2. **Follow semantic versioning** - Users depend on it
3. **Tag every release** - Git tags = release history
4. **Update CHANGELOG** - Document what changed
5. **Test before bumping** - Ensure all tests pass

## CI/CD Integration

For automated releases:

```yaml
# .github/workflows/release.yml
- name: Get version
  run: echo "VERSION=$(cat VERSION)" >> $GITHUB_ENV

- name: Create release
  uses: actions/create-release@v1
  with:
    tag_name: v${{ env.VERSION }}
    release_name: Release v${{ env.VERSION }}
```
