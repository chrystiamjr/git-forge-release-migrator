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
- `--skip-releases`
- `--skip-release-assets`
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
- `--skip-tags` só é permitido quando o forge de destino já tem tags existentes

## Ordem de migração e seleção de releases

Migração sempre prossegue em duas fases, independentemente dos flags `--skip-*`:

1. **Fase de tags**: Todas as tags selecionadas migram antes de qualquer trabalho de release
2. **Fase de releases**: Releases correspondentes a tags semver (`vX.Y.Z`) são criadas/atualizadas após as tags serem concluídas

**Seleção de releases**: Apenas tags que correspondem ao padrão semver `vX.Y.Z` geram releases correspondentes. Por exemplo:
- `v1.0.0`, `v2.1.3` → releases são migradas
- `v2.1.3-rc1`, `release-1.0`, `main`, `alpha` → nenhum release correspondente é migrado (somente tag)

Essa ordem é obrigatória e garante que tags existam antes que releases sejam criadas. Para pular qualquer fase, use `--skip-tags` ou `--skip-releases`.

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

## Help e checks de inicialização

- `gfrm migrate --help` mostra uso e opções específicos de `migrate`.
- O banner ASCII fica reservado para `gfrm` e `gfrm --help`.
- Antes de criar tags, `gfrm migrate` verifica se o forge de destino já contém o objeto de commit referenciado por cada tag de origem que ainda precisa ser migrada.
- Se o histórico necessário estiver ausente, o comando falha cedo com orientações de remediação, incluindo snippets Git para mirror/branch auxiliar e sugestões nativas de GitHub, GitLab ou Bitbucket.
- `--skip-tags` exige que o forge de destino já tenha tags existentes; essa restrição é validada em runtime e bloqueará a migração se violada.
- `--skip-releases` migra somente tags e pula criação/atualização de releases.
- `--skip-release-assets` cria ou atualiza releases sem baixar nem enviar assets de release.
