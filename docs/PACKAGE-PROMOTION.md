# GenixBit OS Package Promotion Policy

## Package Promotion Lifecycle

```text
Build -> Alpha Channel -> Quality Audit -> Testing Channel -> Release Validation -> Stable Channel
```

## Promotion Gate Criteria

1. **Alpha -> Testing**:
   - Package builds cleanly without errors or warnings.
   - `lintian` check returns zero error-level issues.
   - Docker-based disposable package test (`test-packages.sh`) passes install/remove/upgrade.

2. **Testing -> Stable**:
   - Full candidate ISO release validation (`check-release-evidence.sh --require-complete`) returns `PASS`.
   - Maintainer code review and security audit complete.
   - Package manifest signed with active repository subkey.
