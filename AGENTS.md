# AGENTS.md

High-signal context for coding agents working in this repository.

**Global context:** Inherits caveman ultra from `~/.claude/CLAUDE.md`. See that for communication patterns, intensity levels, and core principles.

## Quick Start

1. Read this file and `dart_cli/README.md` before touching code.
2. Run `yarn lint:dart && yarn test:dart && yarn coverage:dart` from the repo root before finalizing changes.
3. All production Dart code lives in `dart_cli/lib/src/`.
4. If behavior visible to users changes, update docs under `website/docs/**` and `website/i18n/pt-BR/**`.
5. Check `Critical Invariants`, `Architecture Map`, and `Change Rules` before making structural decisions.

## Decision Index

- Changing CLI behavior or outputs: read `Product Contract` and `Critical Invariants`.
- Changing runtime orchestration or validation: read `Architecture Map` and `Change Rules`.
- Changing docs or website code: read `Documentation Sync`.
- Handling PR review comments: follow `docs/engineering/pr-review-playbook.md`.
- Creating commits or PR text: follow `docs/engineering/commit-conventions.md` and `docs/engineering/pr-template.md`.

## Product Contract

Project baseline:

- Name: `git-forge-release-migrator`
- Public CLI command: `gfrm`
- Runtime: Dart-only
- Domain: migrate tags, releases, and assets across Git forges with idempotent retry behavior

Supported provider pairs:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket`
- `bitbucket -> github`
- `gitlab -> bitbucket`
- `bitbucket -> gitlab`

Out of scope:

- same-provider migrations
- Bitbucket Data Center / Server

Public CLI commands:

- `gfrm migrate`
- `gfrm resume`
- `gfrm demo`
- `gfrm setup`
- `gfrm settings`

`gfrm settings` actions:

- `init`
- `set-token-env`
- `set-token-plain`
- `unset-token`
- `show`

Behavior that must stay stable:

- `--settings-profile` works for `migrate` and `resume`
- exit code is `0` on success and non-zero on validation or operational failure
- retry command in `summary.json` must use `gfrm resume`
- token precedence is deterministic:
  - `migrate`: settings (`token_env`, then `token_plain`) -> env aliases
  - `resume`: session token context -> settings (`token_env`, then `token_plain`) -> env aliases
- hidden legacy overrides still work when explicitly provided:
  - `--source-token`
  - `--target-token`

Artifact contract:

- every run writes under `migration-results/<timestamp>/`
- required artifacts:
  - `migration-log.jsonl`
  - `summary.json`
  - `failed-tags.txt`
- `summary.json` must keep `schema_version: 2`

## Critical Invariants

1. Tags-first order:
- tags migrate before releases
- `--skip-tags` is only safe when destination tags already exist

2. Release selection:
- release migration targets semver tags only (`vX.Y.Z`)

3. Idempotency and resume:
- terminal checkpoint states prevent repeated work
- completed items are skipped
- incomplete items are retried

4. Bitbucket release model:
- Bitbucket synthetic releases are represented by tag + notes + downloads + `.gfrm-release-<tag>.json`
- missing source Bitbucket manifest must not hard-fail by itself

5. Security:
- never log raw tokens
- preserve provider auth models and current token precedence

## Architecture Map

Main code lives in `dart_cli/lib/src/`.

Core layers:

- `cli.dart`: terminal-facing adapter
- `config.dart` and `config/*`: CLI parsing, settings resolution, and validation
- `application/*`: typed run orchestration and structured preflight
- `migrations/*`: execution core for selection, tag phase, release phase, and summary generation
- `providers/*`: forge adapters and registry
- `core/*`: shared infrastructure, files, settings, HTTP, session store, logging, and types

Boundary rules:

- `cli.dart` should delegate `migrate` and `resume` orchestration to the application layer
- `application/run_service.dart` owns typed orchestration, session persistence, summary finalization, and result mapping
- `application/preflight_service.dart` owns reusable startup readiness checks via typed `PreflightCheck` data
- `migrations/engine.dart` stays execution-only; do not move CLI parsing or provider-specific behavior into it
- provider adapters must produce canonical release data consumed by the engine

## Change Rules

Safe defaults:

- read the impacted flow first before changing a signature or behavior
- preserve unaffected provider pairs
- prefer additive or refactor-safe changes over broad rewrites
- keep docs and tests aligned with implementation
- update this file only when contract, invariants, or architecture actually change

## Token Budget

Default agent behavior for this repository:

- Keep task threads short. When a PR/ticket closes and context is large, suggest starting a fresh thread with a handoff of 20 lines or fewer.
- Do not repeat large plans, diffs, logs, JSON payloads, or previously established context. Summarize only the current decision, blocker, or result.
- For long commands, write output to `/tmp/<task>.log` and report only exit code plus the relevant failing lines or final summary.
- Use focused validation during development. Run full suites only before commit/push or when the risk justifies it.
- For PR review work, inspect unresolved inline threads first. Do not load resolved review history unless investigating stale/duplicate review behavior.
- `$self-review` defaults to active diff plus directly related files. Review the entire project only when explicitly requested.
- Prefer concise final handoffs: changed behavior, validation, commit/push/PR state, and remaining blockers only.

Engineering rules:

- avoid `var`; prefer explicit typing and `final`
- Dart/Flutter production code must use one class/type/enum per file, including private widgets, models, controllers, DTOs, and view models.
- Flutter components must follow the established atomic design layers: atoms, molecules, organisms, and templates. Do not create feature-local design primitives that bypass those layers.
- Test files may group small local fakes or test-only helpers when readability improves and production architecture is unaffected.
- keep helpers small and single-purpose
- keep methods under 120 lines
- keep orchestration-heavy files under 500 lines
- no runtime type dispatch in engine flow (`if (source is ...)`)
- no magic strings or numbers when a named constant is appropriate
- extract shared logic only after 2+ real callsites

Known pitfalls:

- do not call provider APIs directly from `engine.dart`
- do not weaken the `--skip-tags` safety check
- do not change `summary.json` schema version unless explicitly versioning the contract
- do not treat Bitbucket downloads and `.gfrm-release-<tag>.json` as separate units

Agent constraints:

- do not introduce new top-level CLI commands without updating `Product Contract`
- do not change token precedence without updating code and docs together
- do not expand release selection beyond semver-only behavior
- do not add Bitbucket Data Center / Server support
- `roadmap/` is local planning space only; shipped behavior and public docs still live elsewhere

## File Size Exceptions (Architectural Necessity)

The codebase has 7 files exceeding the recommended 500-line limit. These are intentional exceptions justified by their single-responsibility focus and high test coverage. Future refactoring should follow the decomposition strategies outlined below:

### Provider Adapters

**bitbucket.dart** (782 lines, 1 class, ~42 methods)
- **Responsibility:** Complete Bitbucket Cloud API adapter
- **Justification:** Bitbucket's synthetic release model requires tag + downloads + manifest handling in one orchestration point
- **Future decomposition:** Consider extracting into:
  - `bitbucket_api.dart` — core tag/commit operations
  - `bitbucket_downloads.dart` — asset upload/download/pagination logic
  - `bitbucket_manifest.dart` — `.gfrm-release-<tag>.json` manifest handling
- **Blocking:** Keep as-is unless Bitbucket API changes significantly

**gitlab.dart** (610 lines, 1 class, ~31 methods)
- **Responsibility:** Complete GitLab API adapter
- **Justification:** Mirrors GitHub/Bitbucket pattern for consistency; single provider adapter per file
- **Future decomposition:** Consider extracting release asset operations into helper once 2+ adapters share logic
- **Blocking:** Keep as-is unless new provider pair requires shared abstraction

**github.dart** (558 lines, 1 class, ~36 methods)
- **Responsibility:** Complete GitHub API adapter
- **Justification:** Single provider adapter pattern; mirrors GitLab/Bitbucket
- **Future decomposition:** Low priority; functions are already well-scoped
- **Blocking:** Keep as-is

### Configuration & Settings

**config.dart** (622 lines, 0 classes, ~102 functions)
- **Responsibility:** CLI argument parsing, token resolution, runtime options building
- **Justification:** All code is private functions (`_*`) serving the public `CliRequestParser` class. Logical separation by stage:
  1. Provider normalization (`_normalizeProvider`)
  2. Argument extraction helpers (`_requiredString`, `_optionalBool`, etc.)
  3. Runtime option building (`_buildRuntimeOptions`, `_buildDemoRuntime`)
  4. Token resolution flow (`_resolveTokenFromSession`, `_resolveTokenWithFallback`)
  5. Command parsing (`_parseSettingsCommand`, `_parseSetupRequest`, `_parseMigrateRequest`)
- **Future decomposition:** Consider extracting into:
  - `config/token_resolver.dart` — token precedence logic
  - `config/request_builders.dart` — CliRequest construction
  - `config/extraction_helpers.dart` — `_requiredString`, `_optionalBool`, etc.
- **Blocking:** Keep monolithic until refactoring clearly improves testability

**settings.dart** (583 lines, 0 classes, ~95 functions)
- **Responsibility:** Settings file I/O, masking, environment variable integration
- **Justification:** Private function utilities (`_*`) supporting public `SettingsManager` API. Stages:
  1. File operations (`_readSettingsFile`, `_writeSettingsFile`, `_settingsPath`)
  2. Env var mapping (`_envVariableForKey`, `_expandEnvVars`)
  3. Masking logic (`_maskValue`, `_isSensitiveKey`)
  4. Merging strategies (`_mergeSettings`, `_effectiveValue`)
- **Future decomposition:** Consider extracting into:
  - `core/settings_file.dart` — file I/O only
  - `core/settings_masking.dart` — secret masking utilities
  - `core/settings_env_mapper.dart` — environment variable integration
- **Blocking:** Keep monolithic for now; logic is cohesive around settings lifecycle

### Application Orchestration

**run_service.dart** (651 lines, 1 class, ~18 methods)
- **Responsibility:** Run lifecycle orchestration (preflight → execution → summary → session persistence)
- **Justification:** Owns multiple stages but each is essential to transactional correctness:
  1. Preflight validation flow
  2. Checkpoint-aware engine execution
  3. Summary generation & artifact writing
  4. Session context finalization
- **Future decomposition:** Consider extracting into:
  1. `application/run_engine_wrapper.dart` — engine execution + checkpoints
  2. `application/run_summary_service.dart` — summary generation + artifacts
  3. Keep `run_service.dart` for high-level orchestration
- **Blocking:** Keep as-is; decomposition requires careful handling of transactional state

### Migration Phases

**release_phase.dart** (523 lines, 1 class, ~13 methods)
- **Responsibility:** Release migration execution (semver selection, asset handling, idempotency)
- **Justification:** All methods support a single execution flow; fairly cohesive
- **Future decomposition:** Could extract asset handling into helper once shared by >1 caller
- **Blocking:** Low priority; current structure is clean

### Refactoring Priority

1. **High value, low risk:** `config.dart` token resolver logic → separate file
2. **Medium value, medium risk:** `run_service.dart` engine wrapper → separate file
3. **Low value:** Other files are either ~500L or serve essential single flows

**Rule:** Do not refactor unless:
- Tests demonstrate the decomposition improves them (not cosmetic)
- A new feature cannot otherwise be implemented cleanly
- Decomposition is explicitly requested in a design document or RFC

## Validation Commands

Run from repo root unless debugging inside `dart_cli/`:

```bash
yarn lint:dart
yarn test:dart
yarn coverage:dart
```

When `website/` changes, also run:

```bash
yarn docs:build
```

Helpful direct Dart fallback inside `dart_cli/`:

```bash
fvm dart format -l 120 --set-exit-if-changed bin lib test
fvm dart analyze --fatal-infos
fvm dart test
```

## Documentation Sync

`website/` is the source of truth for public docs.

If command contract, auth model, support matrix, output artifacts, or user-visible behavior changes, update:

- `website/docs/**` (EN)
- `website/i18n/pt-BR/docusaurus-plugin-content-docs/current/**` (PT-BR)
- `README.md`
- `dart_cli/README.md` when development or runtime behavior changes

Rules:

- keep EN and PT-BR aligned for public docs changes
- `README.md` and `dart_cli/README.md` outside `website/` should stay short and point back to the docs site
- run `yarn docs:build` before merging website changes

## Short Links to Deeper Docs

- commit conventions: `docs/engineering/commit-conventions.md`
- PR review handling: `docs/engineering/pr-review-playbook.md`
- PR template: `docs/engineering/pr-template.md`
- website and i18n conventions: `docs/engineering/website-conventions.md`
- CI and release details: `website/docs/project/ci-and-release.md`
- macOS release and signing notes: `docs/engineering/release-macos-notes.md`
