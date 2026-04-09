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

Esses arquivos continuam sendo o contrato operacional público de cada execução. Runtime events podem espelhar o mesmo
estado para consumidores internos, mas operadores ainda devem tratar esses artefatos e `gfrm resume` como fonte de
verdade.

## `summary.json`

Expectativas:

- schema version `2`
- metadados do comando executado
- retry command quando houver falhas
- caminhos de artefatos que correspondem aos arquivos gravados na execução

Campos comuns para inspecionar na triagem:

- `retry_command` para continuar a execução com `gfrm resume`
- contadores de tags e releases para entender se a execução parou antes ou depois do início da publicação
- metadados e mensagens de falha que explicam estados de validação bloqueante ou execução parcial

Quando o forge de destino não tem o histórico de commits necessário para tags pendentes, `summary.json` registra a
falha de preflight e deve ser lido junto com `failed-tags.txt`.

## Runtime events

Este runtime também expõe um stream ordenado de eventos por execução para observabilidade, testes e futuros consumidores
de GUI.

- sinks suportados nesta entrega: console, JSONL, in-memory e reducer
- os payloads dos eventos podem espelhar mudanças de status e caminhos de artefatos como `summary.json` e `failed-tags.txt`
- runtime events complementam a observabilidade, mas não substituem `summary.json`, `failed-tags.txt`,
  `migration-log.jsonl` nem `gfrm resume`

## Arquivos de sessão

Por padrão, o estado retomável é salvo em `./sessions/last-session.json`, salvo se `--session-file` for usado.

Use `gfrm resume` para continuar trabalho incompleto. Não reexecute `migrate` apenas para recuperar uma execução parcial.
Se precisar diagnosticar por que um retry ainda não pode prosseguir, inspecione o arquivo de sessão junto com
`summary.json` e `migration-log.jsonl`.
