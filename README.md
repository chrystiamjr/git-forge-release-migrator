# Git Forge Release Migrator (gfrm)

[![License](https://img.shields.io/badge/license-MIT-green)](#)
[![Release](https://img.shields.io/badge/release-semantic--release-informational)](./release.config.cjs)
[![Dart SDK](https://img.shields.io/badge/Dart%20SDK-3.41.0-0175C2?logo=dart&logoColor=white)](https://dart.dev/)

`gfrm` is a Dart CLI to migrate **tags + releases + release notes + assets** between Git forges.

The mainline runtime is now **100% Dart**. Python runtime and Python tests were removed from the default execution path.

## Documentation

- Full CLI reference (EN): [docs/USAGE.md](docs/USAGE.md)
- Full CLI reference (PT-BR): [docs/USAGE.pt-BR.md](docs/USAGE.pt-BR.md)
- README in Portuguese: [README.pt-BR.md](README.pt-BR.md)
- Dart runtime/package guide: [dart_cli/README.md](dart_cli/README.md)
- Agent context for contributors: [AGENTS.md](AGENTS.md)

## Support Matrix

Supported cross-forge pairs:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> github` (Bitbucket Cloud)
- `gitlab -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> gitlab` (Bitbucket Cloud)

Not supported in this phase:

- same-provider migrations (`github->github`, `gitlab->gitlab`, `bitbucket->bitbucket`)
- Bitbucket Data Center / Server

## Requirements

- SDK pinned to `3.41.0` via `.fvmrc`
- `fvm` available for SDK management
- Valid tokens for source/target providers

## Quick Start

```bash
# 1) Install local tooling and hooks
yarn install
yarn prepare

# 2) Activate project SDK via FVM
fvm use 3.41.0

# 3) Install Dart dependencies
cd dart_cli
fvm dart pub get
cd ..

# 4) Run local checks (yarn-first workflow)
yarn lint:dart
yarn test:dart

# 5) Show CLI help
./bin/gfrm --help
```

If your shell `dart` is not bound to FVM globally, run directly with:

```bash
fvm dart run dart_cli/bin/gfrm_dart.dart --help
```

## Command Overview

- `gfrm migrate`: starts a migration from explicit source/target arguments
- `gfrm resume`: resumes from saved session state
- `gfrm demo`: local simulation flow
- `gfrm setup`: interactive bootstrap for settings profile
- `gfrm settings`: token/profile settings management

## Migration Examples

Run migration with explicit tokens:

```bash
./bin/gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --source-token "<gitlab_token>" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --target-token "<github_token>" \
  --from-tag v1.0.0 \
  --to-tag v2.0.0
```

Resume from session (default file is `./sessions/last-session.json` when omitted):

```bash
./bin/gfrm resume --session-file ./sessions/last-session.json
```

Bootstrap settings when starting from zero:

```bash
./bin/gfrm setup
```

## Settings Profiles

Settings commands:

```bash
./bin/gfrm settings init [--profile <name>] [--local] [--yes]
./bin/gfrm settings set-token-env --provider <github|gitlab|bitbucket> --env-name <ENV_NAME> [--profile <name>] [--local]
./bin/gfrm settings set-token-plain --provider <github|gitlab|bitbucket> [--token <value>] [--profile <name>] [--local]
./bin/gfrm settings unset-token --provider <github|gitlab|bitbucket> [--profile <name>] [--local]
./bin/gfrm settings show [--profile <name>]
```

Settings files:

- global: `~/.config/gfrm/settings.yaml` (or `XDG_CONFIG_HOME/gfrm/settings.yaml`)
- local override: `./.gfrm/settings.yaml`

Profile resolution order:

1. explicit `--settings-profile`
2. `defaults.profile` in settings
3. `default`

Token resolution order (`migrate` and `resume`):

1. explicit CLI token (`--source-token`/`--target-token`)
2. session token context (resume)
3. settings provider token (`token_env`, then `token_plain`)
4. env aliases (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, provider aliases)

## Artifacts and Retry

Each run writes under:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Artifacts:

- `migration-log.jsonl`
- `summary.json` (schema v2, includes `schema_version` and executed command)
- `failed-tags.txt`

When failures exist, `summary.json` includes `retry_command` using `gfrm resume`.

## Developer Workflow

```bash
# local quality gates (recommended)
yarn lint:dart
yarn test:dart

# optional smoke flow
./scripts/smoke-test.sh
```

Direct Dart commands are supported, but prefer `yarn` scripts for day-to-day local development.

Husky hooks:

- `pre-commit`: `dart format -l 120 --set-exit-if-changed` + `dart analyze`
- `pre-push`: `dart test`

Test organization:

- `dart_cli/test/unit/**`
- `dart_cli/test/feature/**`
- `dart_cli/test/integration/**`

## Release

CI/release is Dart-only and runs format/analyze/test gates.

- CI: [.github/workflows/ci.yml](.github/workflows/ci.yml)
- Build artifacts (`gfrm` for macOS/Linux/Windows): [.github/workflows/dart-cli-build.yml](.github/workflows/dart-cli-build.yml)
- Semantic release: [.github/workflows/release.yml](.github/workflows/release.yml)

Build artifact names:

- `gfrm-macos` containing binary `gfrm`
- `gfrm-linux` containing binary `gfrm`
- `gfrm-windows` containing binary `gfrm.exe`

Platform first-run notes:

- macOS: if Gatekeeper blocks an unsigned downloaded binary, run `xattr -d com.apple.quarantine ./gfrm`
- Linux: ensure executable bit is set with `chmod +x ./gfrm`
- Windows: unsigned binaries can trigger SmartScreen warnings until code signing is configured
