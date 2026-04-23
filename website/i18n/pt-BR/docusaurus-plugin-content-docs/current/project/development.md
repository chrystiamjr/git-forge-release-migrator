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

## Dev Container

O repositório inclui uma configuração de Dev Container para VS Code e GitHub Codespaces.
Instala Flutter 3.41.0, fvm, Node 22.14.0 e todas as dependências do projeto automaticamente.
Nenhuma configuração manual de ambiente é necessária.

**VS Code:**

1. Instale a extensão [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers).
2. Clone o repositório e abra no VS Code.
3. Clique em **Reopen in Container** quando solicitado, ou execute **Dev Containers: Reopen in Container** pela paleta de comandos.

**GitHub Codespaces:**

Clique em **Code → Codespaces → Create codespace** — o ambiente é montado automaticamente.

**Após o container iniciar:**

```bash
# Executar a CLI
dart run dart_cli/bin/gfrm_dart.dart --help

# Executar os testes
yarn test:dart

# Executar a GUI Flutter (requer display Linux)
cd gui && flutter run -d linux
```

## Testes da GUI

A GUI desktop em Flutter tem suites de testes unitários e E2E. Veja [`gui/README.md` -> Testing](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/gui/README.md#testing) para comandos e estrutura.
