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
- `--skip-releases`
- `--skip-release-assets`
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

## Help e checks de inicialização

- `gfrm resume --help` mostra uso e opções específicos de `resume`.
- O banner ASCII fica reservado para `gfrm` e `gfrm --help`.
- Antes de retomar a fase de tags, `gfrm resume` verifica se o forge de destino já contém o objeto de commit referenciado por cada tag de origem restante.
- Se o histórico necessário estiver ausente, o comando falha cedo com orientações de remediação, incluindo snippets Git para mirror/branch auxiliar e sugestões nativas de GitHub, GitLab ou Bitbucket.
- `--skip-tags` exige que o forge de destino já tenha tags existentes; essa restrição é validada em runtime e bloqueará a migração se violada.
- `--skip-releases` retoma somente a migração de tags e pula criação/atualização de releases.
- `--skip-release-assets` retoma criação/atualização de releases sem baixar nem enviar assets de release.

## Seleção de releases durante o resume

Ao retomar uma migração:

- **Flags de skip salvos** são preservados do comando `migrate` inicial (a menos que substituídos com novos flags `--skip-*` no resume)
- **Seleção de releases ainda aponta apenas para tags semver** (formato `vX.Y.Z`)
- **Releases incompletos** são retentados primeiro, depois tags/releases restantes continuam na ordem padrão de duas fases
- Itens que falharam são retentados apenas se caírem dentro das fases ativas (ex: se `--skip-releases` for definido, falhas de releases não são retentadas)
