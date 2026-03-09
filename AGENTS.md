# AGENTS.md

High-signal context for coding agents working in this repository.

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
- release flow expects destination tags to exist unless `--skip-tags`

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
- `config.dart`
- `models.dart`
- `migrations/engine.dart`
- `migrations/selection.dart`
- `migrations/tag_phase.dart`
- `migrations/release_phase.dart`
- `migrations/summary.dart`
- `providers/registry.dart`
- `providers/{github,gitlab,bitbucket}.dart`
- `core/{http,checkpoint,jsonl,files,session_store,settings,versioning,logging}.dart`
- `core/types/*`

Provider adapters must produce canonical release data consumed by the engine.

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
dart format -l 120 --set-exit-if-changed bin lib test
dart analyze
dart test
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

## Documentation Sync Rules

If command contract, auth model, support matrix, or output artifacts change, update all:

- `README.md`
- `README.pt-BR.md`
- `docs/USAGE.md`
- `docs/USAGE.pt-BR.md`
- `dart_cli/README.md`

## Safe Change Playbook

1. Read impacted flow first (`config`, `engine`, provider adapter, tests).
2. Preserve behavior for unaffected provider pairs.
3. Prefer additive/refactor-safe edits over broad rewrites.
4. Run lint/analyze/tests before finalizing.
5. Keep docs and tests aligned with implementation.

## Non-Goals (Current Phase)

- same-provider migrations
- Bitbucket Data Center compatibility
- expanding release selection beyond current semver-only behavior
