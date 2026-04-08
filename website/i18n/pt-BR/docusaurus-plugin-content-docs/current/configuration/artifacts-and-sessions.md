---
sidebar_position: 4
title: Artefatos e Sessões
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

Campos comuns para inspecionar na triagem:

- `retry_command` para continuar a execução com `gfrm resume`
- contadores de tags e releases para entender se a execução parou antes ou depois do início da publicação
- metadados e mensagens de falha que explicam estados de validação bloqueante ou execução parcial

Quando o forge de destino não tem o histórico de commits necessário para tags pendentes, `summary.json` registra a
falha de preflight e deve ser lido junto com `failed-tags.txt`.

## Arquivos de sessão

Por padrão, o estado retomável é salvo em `./sessions/last-session.json`, salvo se `--session-file` for usado.

Use `gfrm resume` para continuar trabalho incompleto. Não reexecute `migrate` apenas para recuperar uma execução parcial.
Se precisar diagnosticar por que um retry ainda não pode prosseguir, inspecione o arquivo de sessão junto com
`summary.json` e `migration-log.jsonl`.
