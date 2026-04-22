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

## Checks da documentação do site

Quando uma mudança tocar `website/`, a fonte da verdade da documentação pública ainda precisa compilar sem erro:

```bash
yarn docs:build
```

Use `website/` como fonte da verdade da documentação pública. Mantenha `README.md` e `dart_cli/README.md` enxutos e
alinhados com o site.

## Testes da GUI

A GUI desktop em Flutter tem suites de testes unitários e E2E. Veja [`gui/README.md` -> Testing](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/gui/README.md#testing) para comandos e estrutura.
