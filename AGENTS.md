# AGENTS.md

High-signal context for coding agents working in this repository.

## Quick Start

1. Read `AGENTS.md` (this file) and `dart_cli/README.md` before touching code.
2. Run `yarn lint:dart && yarn test:dart` from the repo root before submitting any change.
3. All production code lives in `dart_cli/lib/src/`. Architecture map is below.
4. Check "Documentation Sync Rules" if you change any user-facing behavior.
5. Check "Known Pitfalls" and "Agent Constraints" before making structural decisions.

## Project

- Name: `git-forge-release-migrator`
- Public CLI command: `gfrm`
- Runtime: Dart-only
- Domain: migration of tags/releases/assets across Git forges with strong idempotency and retry behavior

## Scope

Supported cross-forge pairs:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> github` (Bitbucket Cloud)
- `gitlab -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> gitlab` (Bitbucket Cloud)

Out of scope:

- same-provider migrations
- Bitbucket Data Center / Server

## Current CLI Contract (v2)

Root command and subcommands:

- `gfrm migrate`
- `gfrm resume`
- `gfrm demo`
- `gfrm setup`
- `gfrm settings`

Settings actions:

- `init`
- `set-token-env`
- `set-token-plain`
- `unset-token`
- `show`

Important runtime behaviors:

- `--settings-profile` supported by `migrate` and `resume`
- token precedence must remain stable
- retry command in `summary.json` must use `gfrm resume`
- exit code `0` on success, non-zero on validation/operational failure

## Critical Business Invariants

1. Tags-first order:
- tags are migrated before releases
- release flow expects destination tags to exist unless `--skip-tags` is passed
- `--skip-tags` is only valid when destination tags already exist by other means; do not use it as a general shortcut

2. Semver-only release selection:
- selection currently targets `vX.Y.Z`
- non-semver tags are not selected for release migration

3. Idempotency and resume:
- terminal checkpoint states must prevent repeated work
- completed items are skipped
- incomplete items are retried

4. Bitbucket synthetic release model:
- represented by tag + notes + downloads + `.gfrm-release-<tag>.json`

5. Legacy Bitbucket behavior:
- missing manifest on source Bitbucket tag must not hard-fail by itself

## Artifact Contract

Each run writes under:

```text
migration-results/<timestamp>/
```

Required artifacts:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

`summary.json` expectations:

- schema is v2 (`schema_version: 2`)
- includes executed command metadata
- includes retry command when failures exist

## macOS Release Distribution

Release artifact names for macOS:

- `gfrm-macos-intel.zip`
- `gfrm-macos-silicon.zip`

macOS security mode (release workflow variable):

- `MACOS_RELEASE_SECURITY_MODE=permissive` (default): proceed with warnings when Apple signing/notarization credentials are missing
- `MACOS_RELEASE_SECURITY_MODE=strict`: fail macOS jobs when signing/notarization credentials are missing or notarization fails

Notarization credential support and precedence:

1. App Store Connect API key:
   - `APPLE_NOTARY_KEY_ID`
   - `APPLE_NOTARY_ISSUER_ID`
   - `APPLE_NOTARY_API_KEY_P8_BASE64`
2. Apple ID fallback:
   - `APPLE_NOTARY_APPLE_ID`
   - `APPLE_NOTARY_TEAM_ID`
   - `APPLE_NOTARY_APP_PASSWORD`

Required macOS architecture validation in CI:

- `gfrm-macos-intel` must produce `x86_64`
- `gfrm-macos-silicon` must produce `arm64`

Operational note:

- End users can run the compiled `gfrm` binary on a clean Mac without installing Dart/FVM/NVM/Yarn, as long as they download the correct architecture artifact and Gatekeeper requirements are satisfied (signed/notarized preferred; troubleshooting fallback may still be required).

## Auth and Security

Provider auth model:

- GitHub: `Authorization: Bearer <token>`
- GitLab: `PRIVATE-TOKEN` header
- Bitbucket Cloud: `Authorization: Bearer <token>`

Never log raw tokens.

Settings behavior to preserve:

- effective settings = deep merge of global + local
- profile resolution order:
  1. explicit `--settings-profile`
  2. `defaults.profile`
  3. `default`
- token precedence (`migrate`/`resume`) must remain deterministic and documented

## Architecture Map (Dart)

Main code lives in `dart_cli/lib/src/`.

- `cli.dart`
- `cli/settings_setup_command_handler.dart`
- `config.dart`
- `config/arg_parsers.dart`
- `config/validators.dart`
- `config/types/*`
- `models/runtime_options.dart`
- `models/migration_context.dart`
- `migrations/engine.dart`
- `migrations/selection.dart`
- `migrations/tag_phase.dart`
- `migrations/release_phase.dart`
- `migrations/summary.dart`
- `providers/registry.dart`
- `providers/{github,gitlab,bitbucket}.dart`
- `core/{http,checkpoint,jsonl,files,session_store,settings,versioning,logging}.dart`
- `core/exceptions/*`
- `core/types/*`

Provider adapters must produce canonical release data consumed by the engine.

## Safe Change Playbook

1. Read impacted flow first (`config`, `engine`, provider adapter, tests).
2. Identify all callsites and downstream consumers before changing a signature or type.
3. Preserve behavior for unaffected provider pairs.
4. Prefer additive/refactor-safe edits over broad rewrites.
5. Extract logic into small, single-responsibility helpers rather than expanding existing methods.
6. Run lint/analyze/tests before finalizing.
7. Keep docs and tests aligned with implementation.
8. Update `AGENTS.md` if the change affects CLI contract, invariants, or architecture.

## Engineering Rules for This Repo

Apply these rules to new and modified code:

1. Typing and declarations:
- avoid `var`
- prefer explicit typing
- prefer `final` when values do not change

2. File and class organization:
- avoid multiple classes in one file
- one class/type per file is preferred, especially under `core/types/`

3. Readability:
- keep spacing and block structure clear
- avoid dense `if` chains and tightly packed control flow
- prefer small helpers with single responsibility

4. Complexity ceilings:
- no method above 120 lines
- no orchestration file above 500 lines

5. Engine flow:
- avoid main-flow dispatch by runtime type checks (`if (source is ...)` / `if (target is ...)`)
- keep provider-specific rules in adapters

6. Design principles:
- follow Single Responsibility: each class/function does one thing
- follow Open/Closed: extend behavior via new classes or abstractions, not by modifying existing ones
- follow Liskov Substitution: subtypes must be substitutable for their base types
- follow Interface Segregation: prefer narrow interfaces over fat ones
- follow Dependency Inversion: depend on abstractions, not concrete implementations
- apply DRY: extract shared logic as soon as it appears in 2+ real callsites; do not extract speculatively
- follow Clean Architecture layer boundaries: core has no dependency on providers or CLI; providers depend only on core abstractions

7. Anti-patterns to avoid:
- no god classes (classes with unrelated responsibilities)
- no deep nesting (max 3 levels of indentation)
- no magic strings or numbers — use named constants
- no premature abstraction — extract only when 2+ real callsites exist
- no circular dependencies between layers (core ← migrations ← providers ← cli)
- no multi-class files (one class/type per file)
- no large files beyond complexity ceilings defined above

## Formatting and Tooling

- line width: `120`
- project SDK pinned by `.fvmrc` (`3.41.0`)
- use Husky hooks for local quality gates

Primary local commands (from repo root):

```bash
yarn lint:dart
yarn test:dart
```

Equivalent direct commands (inside `dart_cli`, use as fallback/debug):

```bash
fvm dart format -l 120 --set-exit-if-changed bin lib test
fvm dart analyze
fvm dart test
```

## Test Strategy

Test layout:

- `dart_cli/test/unit/**`
- `dart_cli/test/feature/**`
- `dart_cli/test/integration/**`

When changing behavior:

- add/update unit tests for granular logic
- add/update feature tests for CLI and flow-level behavior
- add/update integration tests for end-to-end invariants

Minimum coverage priorities:

- CLI parsing and validation
- settings profile/token resolution
- provider URL parsing and canonical mapping
- checkpoint terminal-state semantics
- retry generation and summary consistency
- idempotency + failed-tags behavior

Run a specific test file (inside `dart_cli`):

```bash
fvm dart test test/unit/path/to/test.dart
```

## Documentation Sync Rules

If command contract, auth model, support matrix, or output artifacts change, update all:

- `README.md`
- `docs/pt_br/README.md`
- `docs/en_us/USAGE.md`
- `docs/pt_br/USAGE.md`
- `dart_cli/README.md`

## Known Pitfalls

- Do not call provider APIs directly from `engine.dart` — use provider adapters.
- Do not add runtime type dispatch (`if (source is X)` / `if (target is X)`) in engine flow — keep it in adapters.
- Bitbucket downloads and `.gfrm-release-<tag>.json` are part of the same atomic synthetic release — always treat them together.
- `summary.json` schema version must stay at `2` unless an explicit versioning decision is made.
- Missing Bitbucket manifest on a source tag must not cause a hard failure — this is a legacy compatibility rule.
- Never log raw tokens anywhere in the codebase.

## Agent Constraints

- Do not introduce new top-level CLI commands without updating the CLI Contract section in this file.
- Do not change token precedence order without updating both code and all documentation files listed in "Documentation Sync Rules".
- Do not bypass or weaken the `--skip-tags` safety check in release phase logic.
- Do not expand release selection beyond semver (`vX.Y.Z`) — this is an explicit non-goal for the current phase.
- Do not add Bitbucket Data Center / Server support — out of scope.

## Non-Goals (Current Phase)

- same-provider migrations
- Bitbucket Data Center compatibility
- expanding release selection beyond current semver-only behavior
