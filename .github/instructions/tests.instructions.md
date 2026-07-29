---
applyTo: "tests/**"
---

# Test Directory Guidelines

When working with tests in this directory:

- **Extend existing tests**: Add new test cases to existing test files whenever possible; only create new test files when covering genuinely distinct functionality
- **Update test runner**: Always add newly created test files to `tests/run_tests.sh` script to ensure they run in CI
- **No legacy API in tests**: When fixing tests, always update them to use the latest API; never add backward compatibility or reintroduce removed APIs for test compatibility—tests must use current production APIs
