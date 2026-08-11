---
applyTo: "tests/**"
---

# Test Directory Guidelines

When working with tests in this directory:

- **Extend existing tests**: Add new test cases to existing test files whenever possible; only create new test files when covering genuinely distinct functionality
- **Test runner**: Spec files are auto-discovered by `tests/framework/supervisor.lua`; a new `*_spec.lua` under `tests/` runs in CI with no runner changes
- **No legacy API in tests**: When fixing tests, always update them to use the latest API; never add backward compatibility or reintroduce removed APIs for test compatibility—tests must use current production APIs
