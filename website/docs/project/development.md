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
