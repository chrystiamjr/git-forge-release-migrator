---
sidebar_position: 1
title: Início Rápido
---

Comece com o binário compilado da sua plataforma, configure os tokens dos providers uma vez e execute uma migração com
URLs explícitas de source e target.

## 1. Baixe o artefato correto

Use a página de releases para baixar o zip da plataforma:

- `gfrm-macos-intel.zip`
- `gfrm-macos-silicon.zip`
- `gfrm-linux.zip`
- `gfrm-windows.zip`
- `checksums-sha256.txt`

Fonte de verdade: [GitHub Releases](https://github.com/chrystiamjr/git-forge-release-migrator/releases).

## 2. Verifique e rode `--help`

Siga [Install and Verify](/getting-started/install-and-verify) para extrair o artefato e confirmar que o binário funciona.
Use `./gfrm <comando> --help` quando precisar das flags específicas de `migrate`, `resume`, `setup` ou `settings`.

## 3. Faça o bootstrap dos settings

```bash
./gfrm setup
```

Isso grava os settings de token no config global por padrão.

## 4. Execute a primeira migração

```bash
./gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo"
```

## 5. Retome se interromper

```bash
./gfrm resume
```

O `gfrm` retoma a partir da sessão salva e ignora o trabalho que já terminou.
Se a execução parar antes da criação das tags porque o forge de destino não tem o histórico de commits necessário,
consulte as orientações de remediação em `summary.json` antes de tentar novamente.
