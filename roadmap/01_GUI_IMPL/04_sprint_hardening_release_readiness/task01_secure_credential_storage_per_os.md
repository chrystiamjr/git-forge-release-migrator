# Task

Implement secure credential storage per operating system for GUI flows.

## Intent

Ensure GUI token handling uses OS-backed secure storage by default and does not silently fall back to unsafe
persistence.

## Detailed scope

- Introduce `CredentialStore` as the shared abstraction for GUI credential persistence.
- Define and implement secure adapters for:
  - macOS Keychain
  - Windows Credential Manager
  - Linux Secret Service
- Define how `CredentialStore.availability()` reports secure-storage support and degraded states.
- Define what happens when secure storage is unavailable, including explicit degraded-mode messaging instead of silent
  fallback.
- Ensure GUI token-entry and settings flows use `CredentialStore` rather than ad hoc local files.
- Preserve existing runtime token precedence; secure storage is a persistence boundary, not a new resolution order.

## Expected changes

- `CredentialStore` exists as a typed contract with operations for read, write, delete, and availability.
- GUI credential persistence routes through OS-backed adapters by default.
- Degraded mode, if supported at all, is explicit and documented as a compromise.
- GUI token persistence stops being an implicit implementation detail and becomes an intentional security boundary.

## Non-goals and guardrails

- Do not default to plain-text storage.
- Do not change CLI token precedence semantics.
- Do not log raw tokens during reads, writes, failures, or diagnostics.
- Do not assume all Linux environments support Secret Service without detection.
- Do not bury secure-storage failures behind generic UI errors.

## Test and validation

- Add adapter-level tests for each supported credential backend.
- Add tests for unavailable secure storage and degraded-mode reporting.
- Add integration scenarios proving GUI token-entry flows use `CredentialStore`.
- Verify sensitive values never appear in logs, errors, or stored plain text by default.
- Keep existing runtime quality gates green with `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- `CredentialStore` exists and is used by GUI credential flows.
- macOS, Windows, and Linux secure-storage adapters are implemented or explicitly handled.
- Plain-text storage is not the default.
- Users can distinguish secure mode from degraded mode when secure storage is unavailable.
