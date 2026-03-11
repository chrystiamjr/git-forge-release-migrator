---
sidebar_position: 4
title: Artifacts and Sessions
---

Cada execução grava artefatos em um diretório de trabalho com timestamp:

```text
migration-results/<timestamp>/
```

Artefatos obrigatórios:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

## `summary.json`

Expectativas:

- schema version `2`
- metadados do comando executado
- retry command quando houver falhas

## Arquivos de sessão

Por padrão, o estado retomável é salvo em `./sessions/last-session.json`, salvo se `--session-file` for usado.

Use `gfrm resume` para continuar trabalho incompleto. Não reexecute `migrate` apenas para recuperar uma execução parcial.
