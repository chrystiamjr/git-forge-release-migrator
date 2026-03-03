# Git Forge Release Migrator (gfrm)

[![Python](https://img.shields.io/badge/python-3.9%2B-blue)](https://www.python.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](#)
[![Release](https://img.shields.io/badge/release-semantic--release-informational)](./release.config.cjs)

Python CLI to migrate **tags + releases + release notes + assets** between Git forges.

It is designed for safe reruns: completed items are skipped, incomplete items are retried, and each execution writes structured output for auditing and retry.

## Contents

- [Support Matrix](#support-matrix)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Copy/Paste Commands](#copypaste-commands)
- [Demo Mode (for GIF recording)](#demo-mode-for-gif-recording)
- [Most Used Flags](#most-used-flags)
- [Output, Retry, and Sessions](#output-retry-and-sessions)
- [Troubleshooting](#troubleshooting)

## Support Matrix

| Source | Target | Status |
|---|---|---|
| `gitlab` | `github` | Available |
| `github` | `gitlab` | Available |
| `bitbucket` | any | Registered, not implemented yet |

## Requirements

| Dependency | Version | Notes |
|---|---|---|
| Python | `>=3.9` | Required to run the CLI |
| `curl` | any | Used to download release assets |
| `gh` (GitHub CLI) | any | Required only for flows that involve GitHub (source or target) |

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
  --source-token "<gitlab_pat>" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --target-token "<github_pat>" \
  --from-tag v3.2.1 \
  --to-tag v3.40.0
```

## Copy/Paste Commands

```bash
# Interactive (recommended first run)
./bin/repo-migrator.py

# Resume last session
./bin/repo-migrator.py --resume-session

# Dry-run only
./bin/repo-migrator.py --dry-run \
  --source-provider gitlab --source-url "https://gitlab.com/group/project" --source-token "<gitlab_pat>" \
  --target-provider github --target-url "https://github.com/org/repo" --target-token "<github_pat>"

# Run only failed tags from previous run
./bin/repo-migrator.py --tags-file ./migration-results/<run>/failed-tags.txt
```

## Demo Mode (for GIF recording)

Use demo mode to simulate migration without real API calls.

```bash
./bin/repo-migrator.py \
  --demo-mode \
  --demo-releases 5 \
  --demo-sleep-seconds 1.2 \
  --source-provider gitlab \
  --source-url "https://gitlab.com/teste" \
  --source-token "foo" \
  --target-provider github \
  --target-url "https://github.com/teste" \
  --target-token "bar" \
  --non-interactive
```

| Mode | Recording |
|---|---|
| Interactive | ![Interactive demo](docs/assets/interactive-mode.gif) |
| Non-interactive | ![Non-interactive demo](docs/assets/non-interactive-mode.gif) |

## Most Used Flags

- `--dry-run`: compute and validate the plan without creating/updating releases.
- `--skip-tags`: migrate releases only.
- `--from-tag` / `--to-tag`: constrain tag range.
- `--tags-file <path>`: run only a specific list of tags.
- `--release-workers <n>` and `--download-workers <n>`: speed tuning.
- `--resume-session`: load+save last session in one command.
- `--non-interactive`: fully scripted run.
- `--progress-bar`: CI-friendly progress output.

Full CLI reference: [docs/USAGE.md](docs/USAGE.md)

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
- If source archives fail, fallback links can still preserve traceability.
- Tokens are never printed in logs.

For GitHub operations, the tool always executes commands as:

```bash
GH_TOKEN="<target_token>" gh ...
```

## Troubleshooting

- `gh: Bad credentials (HTTP 401)` in `--dry-run`:
  - Dry run still validates the target release state, so the target token must be valid.
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

## Documentation

- Full CLI reference and advanced options: [docs/USAGE.md](docs/USAGE.md)
- Portuguese README: [README.pt-BR.md](README.pt-BR.md)
