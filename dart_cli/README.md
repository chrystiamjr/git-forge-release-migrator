# GFRM Dart CLI

Dart runtime package for `git-forge-release-migrator`.
Shared by CLI entrypoints and the desktop GUI workspace in `../gui`.

## Requirements

- Flutter SDK `3.41.0` pinned via `.fvmrc` (ships Dart `3.11.0`)
- `fvm` available for SDK management (`brew install fvm` or see [fvm.app](https://fvm.app/))
- Node.js `22.14.0` pinned via `.nvmrc` (used by semantic-release and yarn tooling)
- `yarn` available for the preferred local workflow

## Quick Start

From the repository root:

```bash
yarn install
yarn prepare

fvm use 3.41.0
yarn fvm:global

yarn get:dart
yarn lint:dart
yarn test:dart
yarn coverage:dart
```

If your shell `dart` is not bound to FVM globally:

```bash
fvm dart run dart_cli/bin/gfrm_dart.dart --help
```

Script reference:

- `yarn install` — installs Node dependencies (semantic-release, hooks, lint tooling)
- `yarn prepare` — sets up Husky git hooks
- `fvm use 3.41.0` — activates the pinned Flutter/Dart SDK for the shell session
- `yarn fvm:global` — sets the FVM version as the global `dart` binary on PATH
- `yarn get:dart` — runs `dart pub get` inside `dart_cli/`
- `yarn lint:dart` — formats and analyzes Dart code
- `yarn test:dart` — runs the full Dart test suite

## Project Structure

```text
dart_cli/
├── bin/
│   └── gfrm_dart.dart     # CLI entrypoint
├── lib/
│   └── src/               # Feature implementation
├── test/
│   ├── unit/              # Isolated function and adapter tests
│   ├── feature/           # Command and feature-level behavior
│   └── integration/       # End-to-end migration flows
└── pubspec.yaml
```

## Entrypoints

- Internal Dart package entrypoint: `dart_cli/bin/gfrm_dart.dart`
- Public command wrapper at repository root: `bin/gfrm`
- Public command contract is `gfrm`; `gfrm_dart.dart` is an implementation detail.

Supported public subcommands:

- `migrate`
- `resume`
- `demo`
- `setup`
- `settings`
- `smoke`

CLI help behavior:

- `gfrm` and `gfrm --help` print the root banner and quick-start usage.
- `gfrm <command> --help` prints command-specific usage and options without the root banner.
- `migrate` and `resume` fail fast before tag creation when the target forge is missing the commit object referenced by a source tag, and the CLI prints remediation guidance instead of waiting for a later provider-side `422`/not-found error.

## Developer Workflow

Preferred local workflow (from repository root):

```bash
yarn lint:dart
yarn test:dart
yarn coverage:dart
```

Equivalent direct Dart/FVM commands (from `dart_cli`):

```bash
cd dart_cli
fvm dart pub get
fvm dart format -l 120 --set-exit-if-changed bin lib test
fvm dart analyze
fvm dart test
```

Running specific test subsets:

```bash
# Unit tests only
fvm dart test test/unit

# Feature tests only
fvm dart test test/feature

# Integration tests only
fvm dart test test/integration

# Single test file
fvm dart test test/unit/some_test.dart
```

Generating coverage reports with `coverde`:

```bash
yarn coverage:dart
```

This command:

- runs the Dart test suite with coverage collection
- generates `coverage/lcov.info` for tooling compatibility
- generates an HTML report under `coverage/html/`
- packages the HTML report as `coverage/coverage_html.zip` using the same cross-platform Node flow used by CI
- enforces the minimum line coverage threshold of `80%`

Open the HTML report locally:

```bash
open coverage/html/index.html
```

If you already have `coverage/lcov.info` and only want to rebuild the HTML report:

```bash
yarn coverage:dart:html
```

If you want a terminal-friendly text report:

```bash
yarn coverage:dart:text
```

The `coverage/lcov.info` file remains available as the technical artifact for LCOV-compatible tools and CI integrations.

CI enforces a minimum line coverage of **80%**, uploads both `coverage/lcov.info` and `coverage/coverage_html.zip`, and
no longer depends on `genhtml`.

`yarn coverage:dart` is part of the expected local validation flow and should pass before changes are finalized.

Husky hooks:

- `pre-commit`: `dart format -l 120 --set-exit-if-changed` + `dart analyze --fatal-infos`
- `pre-push`: `dart test`

Test organization:

- `test/unit/**`: granular unit tests for isolated functions and adapters
- `test/feature/**`: command and feature-level behavior
- `test/integration/**`: end-to-end migration flows and invariants
- keep CLI/logging I/O at the adapter boundary; tests should capture output in memory instead of writing to the real terminal

## Build

Local binary for current host:

```bash
cd dart_cli
fvm dart compile exe bin/gfrm_dart.dart -o build/gfrm
```

After compilation, run the binary directly:

```bash
./build/gfrm --help
./build/gfrm migrate --source-provider gitlab ...
```

The compiled binary requires no Dart/FVM runtime on the target machine.

## Running with Docker

No local Dart or fvm install required — only Docker.

**Build the image** (from repository root):

```bash
docker build -t gfrm .
```

**Run a migration:**

```bash
docker run --rm \
  -v "$(pwd)/migration-results:/app/migration-results" \
  -e GITHUB_TOKEN="$GITHUB_TOKEN" \
  -e GITLAB_TOKEN="$GITLAB_TOKEN" \
  gfrm migrate \
    --source-provider gitlab --source-url https://gitlab.com/owner/repo \
    --target-provider github --target-url https://github.com/owner/repo
```

- `-v` mounts the output directory so artifacts persist after the container exits.
- Pass forge tokens via `-e` environment variables. Never embed tokens in the image.

**Resume a failed run:**

```bash
docker run --rm \
  -v "$(pwd)/migration-results:/app/migration-results" \
  -v "$(pwd)/sessions:/app/sessions" \
  -e GITHUB_TOKEN="$GITHUB_TOKEN" \
  -e GITLAB_TOKEN="$GITLAB_TOKEN" \
  gfrm resume --session-file sessions/last-session.json
```

**Multi-architecture build** (linux/amd64 + linux/arm64, requires Docker Buildx):

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t gfrm . --push
```

---

## Dev Container / GitHub Codespaces

Installs Flutter 3.41.0, fvm, Node 22.14.0, and all project dependencies automatically.
No manual environment setup required. Works in VS Code and GitHub Codespaces.

**VS Code:**

1. Install the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension.
2. Clone the repository and open it in VS Code.
3. Click **"Reopen in Container"** when prompted (or run **Dev Containers: Reopen in Container** from the command palette).

**GitHub Codespaces:**

Click **Code → Codespaces → Create codespace** — environment builds automatically.

**After the container starts:**

```bash
# Run the CLI
cd dart_cli && dart run bin/gfrm_dart.dart --help

# Run tests
yarn test:dart

# Run the Flutter GUI (Linux display required)
cd gui && flutter run -d linux
```

---

## Troubleshooting

**`dart` command not found after `fvm use`**
Run `yarn fvm:global` to link the FVM-managed Dart to your PATH, or prefix commands with `fvm dart`.

**Husky hooks not running**
Run `yarn prepare` to reinstall hooks after a fresh clone or `node_modules` wipe.

**Format check fails on CI but passes locally**
Ensure your local Dart SDK matches the pinned version (`fvm use 3.41.0`). Different Dart versions may format identically-written code differently.

**`pub get` fails with version conflicts**
Delete `dart_cli/.dart_tool/` and `dart_cli/pubspec.lock`, then run `yarn get:dart` again.

## Release

CI/release is Dart-only and runs format/analyze/test gates.

- CI: `.github/workflows/quality-checks.yml`
- Build artifacts workflow: `.github/workflows/release.yml` (job `build-release-assets`)
- Semantic release workflow: `.github/workflows/release.yml`
- Semantic release config: `release.config.cjs`

- `quality-checks.yml` runs automatically on `pull_request`
- `release.yml` runs automatically on `push` to `main`
- there is no manual `workflow_dispatch` path for these pipelines

Release archive names:

- `gfrm-macos-intel.zip`
- `gfrm-macos-silicon.zip`
- `gfrm-linux.zip`
- `gfrm-windows.zip`
- `checksums-sha256.txt` — SHA256 checksums for all zip artifacts

macOS release security mode (`.github/workflows/release.yml`):

- `MACOS_RELEASE_SECURITY_MODE=permissive` (default)
- `MACOS_RELEASE_SECURITY_MODE=strict`
