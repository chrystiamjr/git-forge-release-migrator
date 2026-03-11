---
sidebar_position: 2
title: Desenvolvimento
---

A orientação de desenvolvimento e runtime está em [`dart_cli/README.md`](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/dart_cli/README.md).

## Checks locais principais

A partir da raiz do repositório:

```bash
yarn lint:dart
yarn test:dart
yarn coverage:dart
./scripts/smoke-test.sh
```

## Artefatos de coverage

- `dart_cli/coverage/lcov.info`
- `dart_cli/coverage/html/`
- `dart_cli/coverage/coverage_html.zip`

O CI exige cobertura mínima de `80%`.
