---
sidebar_position: 2
title: Development
---

Developer-focused runtime guidance lives in [`dart_cli/README.md`](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/dart_cli/README.md).

## Core local checks

From the repository root:

```bash
yarn lint:dart
yarn test:dart
yarn coverage:dart
```

## Coverage artifacts

- `dart_cli/coverage/lcov.info`
- `dart_cli/coverage/html/`
- `dart_cli/coverage/coverage_html.zip`

CI enforces a minimum line coverage of `80%`.

## Website docs checks

When a change touches `website/`, the public docs source of truth must still build cleanly:

```bash
yarn docs:build
```

Use `website/` as the public documentation source of truth. Keep `README.md` and `dart_cli/README.md` concise and
aligned with the site.

## Dev Container

The repository ships a Dev Container configuration for VS Code and GitHub Codespaces.
It installs Flutter 3.41.0, fvm, Node 22.14.0, and all project dependencies automatically.
No manual environment setup is required.

**VS Code:**

1. Install the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension.
2. Clone the repository and open it in VS Code.
3. Click **Reopen in Container** when prompted, or run **Dev Containers: Reopen in Container** from the command palette.

**GitHub Codespaces:**

Click **Code → Codespaces → Create codespace** — the environment builds automatically.

**After the container starts:**

```bash
# Run the CLI
cd dart_cli && dart run bin/gfrm_dart.dart --help

# Run the test suite
yarn test:dart

# Run the Flutter GUI (requires Linux display)
cd gui && flutter run -d linux
```

## GUI testing

The Flutter desktop GUI has unit and E2E test suites. See [`gui/README.md` → Testing](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/gui/README.md#testing) for commands and structure.
