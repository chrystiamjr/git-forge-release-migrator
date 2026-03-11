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
./scripts/smoke-test.sh
```

## Coverage artifacts

- `dart_cli/coverage/lcov.info`
- `dart_cli/coverage/html/`
- `dart_cli/coverage/coverage_html.zip`

CI enforces a minimum line coverage of `80%`.
