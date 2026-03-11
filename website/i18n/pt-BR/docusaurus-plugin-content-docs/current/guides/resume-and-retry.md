---
sidebar_position: 2
title: Resume and Retry
---

Use `gfrm resume` sempre que uma execução for interrompida ou falhar parcialmente.

## Resume padrão

```bash
gfrm resume
```

## Arquivo de sessão explícito

```bash
gfrm resume --session-file ./sessions/last-session.json
```

## O que é ignorado

- itens concluídos permanecem concluídos
- estados terminais de checkpoint evitam trabalho duplicado
- itens incompletos são tentados novamente

## Triagem de falhas

Inspecione:

- `failed-tags.txt`
- `summary.json`
- `migration-log.jsonl`

Quando existem falhas, `summary.json` inclui um `retry_command` com `gfrm resume`.
