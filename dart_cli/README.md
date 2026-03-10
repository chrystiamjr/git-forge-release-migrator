# gfrm Dart CLI

Dart runtime package for `git-forge-release-migrator`.

## SDK and Version Management

Project SDK is pinned to `3.41.0` via `.fvmrc` in repository root.

Recommended local setup:

```bash
cd ..
fvm use 3.41.0
```

Run Dart commands with FVM for deterministic behavior:

```bash
fvm dart --version
fvm dart pub get
```

## Entrypoints

- Internal Dart package entrypoint: `dart_cli/bin/gfrm_dart.dart`
- Public command wrapper at repository root: `bin/gfrm`
- Public command contract is `gfrm`; `gfrm_dart.dart` is an implementation detail for package/runtime workflows.

Supported public subcommands:

- `migrate`
- `resume`
- `demo`
- `setup`
- `settings`

## Development

Preferred local workflow (from repository root):

```bash
yarn install
yarn prepare
yarn get:dart
yarn lint:dart
yarn test:dart
```

Equivalent direct Dart/FVM commands:

```bash
# from dart_cli
cd dart_cli
fvm dart pub get
fvm dart format -l 120 --set-exit-if-changed bin lib test
fvm dart analyze
fvm dart test
```

## Test Organization

Tests are grouped by scope:

- `test/unit/**`: granular unit tests for isolated functions and adapters
- `test/feature/**`: command and feature-level behavior
- `test/integration/**`: end-to-end migration flows and invariants

## Build

Local binary for current host:

```bash
cd dart_cli
fvm dart compile exe bin/gfrm_dart.dart -o build/gfrm
```

CI produces cross-platform binaries (`gfrm`) in:

- `.github/workflows/dart-cli-build.yml`
