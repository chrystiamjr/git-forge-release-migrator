# AGENTS.md

This document is a high-signal context file for AI coding agents working in this repository.

## Project Purpose

`git-forge-release-migrator` (`gfrm`) is a Python CLI that migrates:

- tags
- releases
- release notes
- release assets

between Git forges, with strong retry/idempotency behavior.

## Current Business Scope

Supported cross-forge pairs:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket`
- `bitbucket -> github`
- `gitlab -> bitbucket`
- `bitbucket -> gitlab`

Not supported in this phase:

- same-provider migrations (`github->github`, `gitlab->gitlab`, `bitbucket->bitbucket`)
- Bitbucket Data Center / Server hosts

Bitbucket scope in this project is **Bitbucket Cloud only** (`bitbucket.org`).

## Key Product Decisions

1. **Tags-first migration order**
   - Tags are migrated before releases.
   - Release processing expects destination tags to exist (unless `--skip-tags` is used).

2. **Semver-only release selection**
   - Release tags selected by the engine currently match `vX.Y.Z`.
   - Non-semver tags are ignored for release migration selection.

3. **Idempotent reruns are a core requirement**
   - Terminal checkpoint states prevent repeated work.
   - Existing complete releases are skipped.
   - Existing incomplete releases are retried/resumed.

4. **Bitbucket release model is synthetic**
   - Bitbucket does not use a first-class release entity in the same way as GitHub/GitLab.
   - This project models Bitbucket release state as:
     - tag
     - tag message (release notes)
     - files in Downloads
     - per-tag manifest file (`.gfrm-release-<tag>.json`)

5. **Legacy Bitbucket compatibility rule**
   - If a Bitbucket source tag has no manifest, migration still proceeds.
   - Notes and traceability are preserved.
   - Missing binary assets alone do not fail migration in this specific legacy case.

## Architecture Map

Main package: `src/git_forge_release_migrator/`

- `cli.py`
  - entrypoint orchestration
  - resolves runtime options
  - allocates run workdir
  - saves session
  - invokes migration engine
- `config.py`
  - CLI args parsing (`RawCLIOptions`)
  - normalization/validation
  - interactive prompting for missing inputs
  - runtime option construction (`RuntimeOptions`)
- `models.py`
  - `RuntimeOptions`
  - `MigrationContext`
- `providers/`
  - `base.py`: provider interface + `ProviderRef`
  - `registry.py`: provider instances + pair enablement matrix
  - `github.py`, `gitlab.py`, `bitbucket.py`: provider-specific API logic and canonical mapping
- `migrations/engine.py`
  - core migration orchestration and per-pair flows
  - tag migration, release migration, retries, checkpoint/log updates, summary generation
- `core/`
  - `http.py`: curl-based HTTP helpers + retry/auth error behavior
  - `shell.py`: shell execution helpers
  - `checkpoint.py`: checkpoint append/load + terminal status predicates
  - `jsonl.py`: structured log writer
  - `files.py`: file/dir helper functions
  - `session_store.py`: session persistence with safe file permissions
  - `versioning.py`: semver comparison helper

## Provider Contract (Important)

All providers implement/participate in a normalized release shape consumed by the engine:

```json
{
  "tag_name": "v1.2.3",
  "name": "Release v1.2.3",
  "description_markdown": "...",
  "commit_sha": "...",
  "assets": {
    "links": [{"name":"...","url":"...","direct_url":"...","type":"..."}],
    "sources": [{"name":"...","url":"...","format":"..."}]
  }
}
```

Notes:

- The engine depends on this canonical shape for cross-provider behavior.
- Keep field semantics stable when modifying adapters.

## Engine Invariants

In `migrations/engine.py`, preserve these invariants:

- checkpoint signature includes migration order + source/target resources + tag range
- terminal checkpoint statuses:
  - release: `created`, `updated`, `skipped_existing`
  - tag: `tag_created`, `tag_skipped_existing`
- summary always writes:
  - `summary.json`
  - `failed-tags.txt`
- failures in tags or releases should fail the run with non-zero outcome

## Artifacts Contract

Each run writes under:

```text
migration-results/<timestamp>/
```

Expected artifacts:

- `migration-log.jsonl` (per-step structured records)
- `summary.json` (aggregated counts + paths + retry command)
- `failed-tags.txt` (sorted list of failed tags)

## Auth Model

- GitHub: `GH_TOKEN` runtime env override for `gh` commands.
- GitLab: `PRIVATE-TOKEN` header.
- Bitbucket Cloud: `Authorization: Bearer <token>`.

Do not add token values to logs.

## Testing Strategy

Primary test suite: `python3 -m unittest discover -s tests -p 'test_*.py'`

Key coverage buckets:

- config parsing/validation
- provider URL parsing + canonical mapping
- pair matrix behavior
- engine integration behavior (retry, checkpoint, dry-run, failed-tags)
- Bitbucket cross-forge logic and manifest semantics

When changing migration behavior:

- add/adjust integration tests in `tests/test_engine_integration.py`
- add/adjust adapter tests in `tests/test_providers.py`
- add/adjust pair matrix tests in `tests/test_registry.py`

## Safe Change Playbook for AI Agents

1. Read pair matrix and target flow in `providers/registry.py` and `migrations/engine.py` first.
2. Preserve current behavior for unaffected pairs.
3. Keep docs in sync when changing supported pairs, auth model, or output contracts:
   - `README.md`
   - `README.pt-BR.md`
   - `docs/USAGE.md`
   - `docs/USAGE.pt-BR.md`
4. Run full test suite after changes.
5. Prefer additive/refactor-safe edits over broad rewrites in engine logic.

## Non-Goals (Current Phase)

- same-provider migrations
- Bitbucket Data Center compatibility
- broad tag formats beyond current semver selection logic
