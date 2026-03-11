---
sidebar_position: 1
title: migrate
---

Inicia uma migração a partir de parâmetros explícitos de source e target.

## Sintaxe

```bash
gfrm migrate \
  --source-provider <github|gitlab|bitbucket> \
  --source-url <url> \
  --target-provider <github|gitlab|bitbucket> \
  --target-url <url> \
  [opções]
```

## Flags obrigatórias

- `--source-provider`
- `--source-url`
- `--target-provider`
- `--target-url`

## Opções principais

- `--settings-profile <nome>`
- `--skip-tags`
- `--from-tag <tag>`
- `--to-tag <tag>`
- `--dry-run`
- `--download-workers <1..16>`
- `--release-workers <1..8>`
- `--workdir <dir>`
- `--session-file <caminho>`
- `--no-banner`
- `--quiet`
- `--json`

## Regras de validação

- source e target precisam ser providers diferentes
- `--download-workers` deve ser `1..16`
- `--release-workers` deve ser `1..8`
- se `--from-tag` e `--to-tag` estiverem presentes, a ordem semver precisa ser válida

## Fontes de token

1. token em settings (`token_env`, depois `token_plain`)
2. aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)

## Exemplo

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --settings-profile default \
  --from-tag v1.0.0 \
  --to-tag v2.0.0
```
