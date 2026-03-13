# AGENTS.md

High-signal context for coding agents working in this repository.

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

Engineering rules:

- avoid `var`; prefer explicit typing and `final`
- prefer one class or type per file
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

