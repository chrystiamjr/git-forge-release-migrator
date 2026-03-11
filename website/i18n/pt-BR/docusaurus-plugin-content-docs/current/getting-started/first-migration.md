---
sidebar_position: 3
title: First Migration
---

Este é o caminho mínimo útil para uma migração real.

## Configure tokens uma vez

```bash
./gfrm setup
```

Use [Settings Profiles](/configuration/settings-profiles) se precisar de mais de um ambiente.

## Execute uma migração real

```bash
./gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo"
```

## Valide sem escrever no destino

```bash
./gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --dry-run
```

## Inspecione os artefatos

Toda execução grava em:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Artefatos esperados:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

Se houver falhas, `summary.json` inclui um `retry_command` com `gfrm resume`.
