# Git Forge Release Migrator (gfrm)

[![Python](https://img.shields.io/badge/python-3.9%2B-blue)](https://www.python.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](#)
[![Release](https://img.shields.io/badge/release-semantic--release-informational)](./release.config.cjs)

Python CLI to migrate **tags + releases + release notes + assets** between Git forges.

Designed for safe reruns: completed items are skipped, incomplete items are retried, and each execution writes structured output for auditing and retry.

## Documentation

- Full CLI reference: [docs/USAGE.md](docs/USAGE.md)
- Portuguese CLI reference: [docs/USAGE.pt-BR.md](docs/USAGE.pt-BR.md)
- Portuguese README: [README.pt-BR.md](README.pt-BR.md)
- AI agent context guide: [AGENTS.md](AGENTS.md)

## Contents

- [Support Matrix](#support-matrix)
- [Provider Model](#provider-model)
- [Bitbucket Manifest Contract](#bitbucket-manifest-contract)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Command Recipes](#command-recipes)
- [Tag Selection Rules](#tag-selection-rules)
- [Output, Retry, and Sessions](#output-retry-and-sessions)
- [Safety Model](#safety-model)
- [Troubleshooting](#troubleshooting)
- [Developer Setup](#developer-setup)
- [Release Process (this project)](#release-process-this-project)

## Support Matrix

| Source | Target | Status |
|---|---|---|
| `gitlab` | `github` | Available |
| `github` | `gitlab` | Available |
| `github` | `bitbucket` | Available (Bitbucket Cloud) |
| `bitbucket` | `github` | Available (Bitbucket Cloud) |
| `gitlab` | `bitbucket` | Available (Bitbucket Cloud) |
| `bitbucket` | `gitlab` | Available (Bitbucket Cloud) |

Notes:

- Same-provider migrations are intentionally unsupported in this phase (`github->github`, `gitlab->gitlab`, `bitbucket->bitbucket`).
- Bitbucket support is **Bitbucket Cloud only** (`bitbucket.org`).

## Provider Model

- `gitlab` release model: GitLab release + links + sources.
- `github` release model: GitHub release + assets + auto source archives.
- `bitbucket` release model in this project: **tag + tag message + files in Downloads**.

This means Bitbucket releases are represented through tags and download artifacts, not a first-class "Release" entity in the same shape as GitHub/GitLab.

## Bitbucket Manifest Contract

For Bitbucket targets, each migrated tag writes a manifest file in Downloads:

- filename: `.gfrm-release-<tag>.json`
- purpose: idempotency and retry decisions
- minimum fields:
  - `version`
  - `tag_name`
  - `release_name`
  - `notes_hash`
  - `uploaded_assets`
  - `missing_assets`
  - `updated_at`

Behavior on legacy Bitbucket tags without manifest:

- migration still proceeds (notes + traceability link)
- assets may be empty
- migration does not fail just because manifest is missing

## Requirements

| Dependency | Version | Notes |
|---|---|---|
| Python | `>=3.9` | Required to run the CLI |
| `curl` | any | Used for API interactions and asset transfer |
| `gh` (GitHub CLI) | any | Required only when a flow involves GitHub |

Install `gh`: https://cli.github.com

## Quick Start

1. Install:

```bash
pip install -e .
```

2. Run interactive mode:

```bash
./bin/repo-migrator.py
```

3. Run non-interactive mode:

```bash
./bin/repo-migrator.py \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --source-token "<gitlab_token>" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --target-token "<github_token>" \
  --from-tag v3.2.1 \
  --to-tag v3.40.0
```

## Command Recipes

```bash
# Interactive (recommended first run)
./bin/repo-migrator.py

# Resume last session
./bin/repo-migrator.py --resume-session

# Dry-run only (GitLab -> GitHub)
./bin/repo-migrator.py --dry-run \
  --source-provider gitlab --source-url "https://gitlab.com/group/project" --source-token "<gitlab_token>" \
  --target-provider github --target-url "https://github.com/org/repo" --target-token "<github_token>"

# GitHub -> Bitbucket Cloud
./bin/repo-migrator.py --non-interactive \
  --source-provider github --source-url "https://github.com/org/repo" --source-token "<github_token>" \
  --target-provider bitbucket --target-url "https://bitbucket.org/workspace/repo" --target-token "<bitbucket_bearer>"

# Bitbucket Cloud -> GitLab
./bin/repo-migrator.py --non-interactive \
  --source-provider bitbucket --source-url "https://bitbucket.org/workspace/repo" --source-token "<bitbucket_bearer>" \
  --target-provider gitlab --target-url "https://gitlab.com/group/project" --target-token "<gitlab_token>"

# Retry only failed tags from previous run
./bin/repo-migrator.py --resume-session --tags-file ./migration-results/<run>/failed-tags.txt
```

## Tag Selection Rules

- The migration engine currently selects tags that match `vX.Y.Z` semantic format.
- `--from-tag` and `--to-tag` are inclusive.
- `--tags-file` is an additional filter on top of provider-discovered releases.

## Output, Retry, and Sessions

Each run writes to:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Generated files:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

Session defaults:

- session file: `./sessions/last-session.json`
- token mode: `env` (recommended; does not store token plaintext)

## Safety Model

- Tag migration runs before release migration.
- Existing complete release is skipped.
- Existing incomplete release is retried/updated.
- Checkpoints are used to avoid reprocessing terminal states.
- Tokens are never printed in logs.

For GitHub operations, commands are executed with runtime token override:

```bash
GH_TOKEN="<target_token>" gh ...
```

For Bitbucket operations in this phase, API auth is expected as:

```text
Authorization: Bearer <token>
```

## Troubleshooting

- `gh: Bad credentials (HTTP 401)` in `--dry-run`:
  - Dry run still validates target release state, so target token must be valid.
- `Only Bitbucket Cloud URLs are supported in this phase`:
  - Use `https://bitbucket.org/<workspace>/<repo>`.
- `pip install -e .[dev]` fails in `zsh`:
  - Use quotes: `pip install -e '.[dev]'`.

## Developer Setup

```bash
pip install -e '.[dev]'
./scripts/install-hooks.sh
```

Configured hooks:

- `pre-commit`: lint + formatting checks
- `commit-msg`: commit message validation with Commitizen
- `pre-push`: full test suite

Run tests manually:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

## Release Process (this project)

This repository uses `semantic-release` + GitHub Actions on `main`.

- Conventional Commits drive version bumps.
- New tag `vX.Y.Z` is created automatically.
- GitHub Release and changelog are generated.

See: [CHANGELOG.md](CHANGELOG.md), [release.config.cjs](release.config.cjs), [.github/workflows/release.yml](.github/workflows/release.yml)
