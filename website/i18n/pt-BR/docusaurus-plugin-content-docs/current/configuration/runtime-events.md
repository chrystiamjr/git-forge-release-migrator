---
sidebar_position: 5
title: Runtime Events
---

O GFRM agora emite um stream ordenado de runtime events para cada execução.

## Para que serve

Runtime events servem para:

- observabilidade de runtime
- asserções de teste
- futuras atualizações de estado da GUI

Eles complementam os artefatos voltados a operadores, mas não substituem `summary.json`, `failed-tags.txt`,
`migration-log.jsonl` nem `gfrm resume`.

## Ordenação e sinks

- a ordenação dos eventos é autoritativa dentro de cada execução
- sinks suportados nesta entrega: console, JSONL, in-memory e reducer
- a formatação específica de cada sink fica fora do publisher ordenado
- sinks agora declaram um modo explícito de falha: `optional` ou `mandatory`

O sink JSONL é uma implementação consumidora de runtime events. O artefato público da execução para operadores continua
sendo `migration-log.jsonl`.

## Política de falha

- sinks `optional` operam em best-effort: falhas são registradas e a execução continua
- sinks `mandatory` falham a execução imediatamente quando não conseguem consumir um evento

Use `mandatory` só quando o consumidor fizer parte do contrato obrigatório de runtime da camada que embute o GFRM.

## `RunState` derivado

O sink reducer pode derivar um snapshot tipado de `RunState` a partir do stream ordenado de eventos.

O modelo atual do snapshot inclui:

- status de lifecycle
- fase ativa
- resumo de preflight
- contadores de tags e releases
- entradas de progresso por tag e por release
- caminhos de artefatos
- comando de retry e status final de conclusão
- contexto da falha mais recente

Esse estado serve para GUI, testes e diagnósticos in-process. Ele permanece provider-agnostic e seguro para replay
porque é derivado apenas dos runtime events canônicos acima.

## Famílias de eventos

Exemplos de runtime events expostos nesta entrega:

- `run_started`
- `preflight_completed`
- `tag_migrated`
- `release_migrated`
- `artifact_written`
- `run_completed`
- `run_failed`

Esses eventos podem espelhar estado de progresso e caminhos de artefatos gravados, incluindo `summary.json` e
`failed-tags.txt`.

## Contrato público

Use runtime events quando você precisar de visibilidade ordenada do runtime dentro da aplicação, testes ou futuras
camadas de GUI. Use `summary.json`, `failed-tags.txt`, `migration-log.jsonl` e `gfrm resume` quando precisar do
contrato operacional público para triagem e recuperação.
