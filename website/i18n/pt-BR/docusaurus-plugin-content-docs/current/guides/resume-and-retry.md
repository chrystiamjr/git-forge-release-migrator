---
sidebar_position: 2
title: Retomar e Repetir
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

## Histórico ausente no destino

Se `resume` ou `migrate` parar antes da criação das tags porque o forge de destino não contém o objeto de commit
referenciado por uma tag da origem:

- leia a dica de preflight em `summary.json`
- inspecione `failed-tags.txt` para ver quais tags foram bloqueadas
- alinhe o histórico do repositório antes de tentar novamente

Padrões seguros de remediação:

- espelhar o repositório de origem no destino quando o destino puder receber o histórico completo
- publicar uma branch auxiliar com os objetos de commit ausentes quando a branch default atual precisar ser preservada
- usar `--skip-tags` somente quando as tags solicitadas já existirem no forge de destino
