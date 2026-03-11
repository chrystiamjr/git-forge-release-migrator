---
sidebar_position: 2
title: resume
---

Retoma uma migração a partir do estado salvo em sessão.

## Sintaxe

```bash
gfrm resume [opções]
```

## Opções principais

- `--session-file <caminho>`
- `--settings-profile <nome>`
- `--skip-tags`
- `--from-tag <tag>`
- `--to-tag <tag>`
- `--dry-run`
- `--download-workers <1..16>`
- `--release-workers <1..8>`
- `--workdir <dir>`
- `--no-banner`
- `--quiet`
- `--json`

## Ordem de resolução de token

1. contexto de token da sessão
2. token em settings (`token_env`, depois `token_plain`)
3. aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)

## Exemplo

```bash
gfrm resume --session-file ./sessions/last-session.json
```

Se o arquivo de sessão padrão não existir, inicie uma nova execução com `migrate`.
