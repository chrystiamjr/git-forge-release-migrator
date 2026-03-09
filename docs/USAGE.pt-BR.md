# Referência da CLI (Português)

Este documento reflete o contrato atual da CLI Dart (`gfrm`).

## Comandos Canônicos

```bash
./bin/gfrm migrate [opções]
./bin/gfrm resume [opções]
./bin/gfrm demo [opções]
./bin/gfrm setup [opções]
./bin/gfrm settings <ação> [opções]
```

## Desenvolvimento Local (Yarn Primeiro)

Validações recomendadas na raiz do repositório:

```bash
yarn lint:dart
yarn test:dart
./scripts/smoke-test.sh
```

Comandos Dart diretos continuam funcionando, mas a documentação prioriza scripts `yarn` para o fluxo diário.

## Providers e Aliases

Providers suportados:

- `github` (alias: `gh`)
- `gitlab` (alias: `gl`)
- `bitbucket` (alias: `bb`, apenas Bitbucket Cloud)

Pares cross-forge suportados:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket`
- `bitbucket -> github`
- `gitlab -> bitbucket`
- `bitbucket -> gitlab`

Não suportado:

- migrações same-provider
- Bitbucket Data Center / Server

## `migrate`

Inicia a migração com parâmetros explícitos de origem e destino.

Sintaxe:

```bash
./bin/gfrm migrate \
  --source-provider <github|gitlab|bitbucket> \
  --source-url <url> \
  [--source-token <token>] \
  --target-provider <github|gitlab|bitbucket> \
  --target-url <url> \
  [--target-token <token>] \
  [opções]
```

Obrigatórios:

- `--source-provider`
- `--source-url`
- `--target-provider`
- `--target-url`

Fontes de token (ordem):

1. token explícito na CLI (`--source-token` / `--target-token`)
2. token em settings (`token_env`, depois `token_plain`)
3. aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)

Principais opções:

- `--settings-profile <nome>`
- `--skip-tags`
- `--from-tag <tag>`
- `--to-tag <tag>`
- `--workdir <dir>`
- `--log-file <path>`
- `--checkpoint-file <path>`
- `--tags-file <path>`
- `--download-workers <1..16>` (padrão: `4`)
- `--release-workers <1..8>` (padrão: `1`)
- `--dry-run`
- `--save-session` (padrão: habilitado)
- `--no-save-session`
- `--session-file <path>`
- `--session-token-mode <env|plain>` (padrão: `env`)
- `--session-source-token-env <nome>` (padrão: `GFRM_SOURCE_TOKEN`)
- `--session-target-token-env <nome>` (padrão: `GFRM_TARGET_TOKEN`)
- `--no-banner`
- `--quiet`
- `--json`
- `--progress-bar`

Regras de validação:

- `--download-workers` deve estar em `1..16`
- `--release-workers` deve estar em `1..8`
- se `--from-tag` e `--to-tag` forem definidos, `from <= to`

## `resume`

Retoma uma execução a partir de sessão persistida.

Sintaxe:

```bash
./bin/gfrm resume [opções]
```

Principais opções:

- `--session-file <path>` (padrão quando omitido: `./sessions/last-session.json`)
- `--settings-profile <nome>`
- `--skip-tags`
- `--from-tag <tag>`
- `--to-tag <tag>`
- `--workdir <dir>`
- `--log-file <path>`
- `--checkpoint-file <path>`
- `--tags-file <path>`
- `--download-workers <1..16>`
- `--release-workers <1..8>`
- `--dry-run`
- `--save-session` (padrão: habilitado)
- `--no-save-session`
- `--session-token-mode <env|plain>`
- `--session-source-token-env <nome>`
- `--session-target-token-env <nome>`
- `--no-banner`
- `--quiet`
- `--json`
- `--progress-bar`

Fontes de token (ordem):

1. token do contexto de sessão (`source_token` ou `source_token_env`, idem para target)
2. token em settings (`token_env`, depois `token_plain`)
3. aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)

Se precisar forçar token no fluxo `resume`, configure-o via settings ou variáveis de ambiente antes de executar.

## `demo`

Executa o modo de simulação local.

Sintaxe:

```bash
./bin/gfrm demo [opções]
```

Principais opções:

- `--source-provider`, `--source-url`, `--source-token`
- `--target-provider`, `--target-url`, `--target-token`
- `--demo-releases <1..100>` (padrão: `5`)
- `--demo-sleep-seconds <segundos>` (padrão: `1.0`, deve ser `>= 0`)
- `--skip-tags`
- `--dry-run`
- `--workdir`, `--log-file`, `--checkpoint-file`, `--tags-file`
- `--download-workers`, `--release-workers`
- `--session-file`, `--session-token-mode`, `--session-source-token-env`, `--session-target-token-env`
- `--no-banner`, `--quiet`, `--json`, `--progress-bar`

## `setup`

Bootstrap interativo para configuração inicial de settings.

Sintaxe:

```bash
./bin/gfrm setup [opções]
```

Opções:

- `--profile <nome>`
- `--local` (escreve em `./.gfrm/settings.yaml`)
- `--yes` (modo não interativo com defaults)
- `--force` (executa setup mesmo com mappings já existentes)

## `settings`

Ações de settings:

```bash
./bin/gfrm settings init [--profile <nome>] [--local] [--yes]
./bin/gfrm settings set-token-env --provider <github|gitlab|bitbucket> --env-name <ENV_NAME> [--profile <nome>] [--local]
./bin/gfrm settings set-token-plain --provider <github|gitlab|bitbucket> [--token <valor>] [--profile <nome>] [--local]
./bin/gfrm settings unset-token --provider <github|gitlab|bitbucket> [--profile <nome>] [--local]
./bin/gfrm settings show [--profile <nome>]
```

Comportamento:

- caminho global: `~/.config/gfrm/settings.yaml` (ou `XDG_CONFIG_HOME/gfrm/settings.yaml`)
- caminho local de override: `./.gfrm/settings.yaml`
- settings efetivo = deep-merge(global, local)
- `settings show` mascara `token_plain`
- `settings init` apenas lê arquivos de shell (`.zshrc`, `.zprofile`, `.bashrc`, `.bash_profile`)

Resolução de perfil:

1. `--settings-profile` explícito (em `migrate`/`resume`)
2. `defaults.profile` em settings
3. `default`

## Invariantes de Execução

- ordem da migração é sempre tags-first
- seleção de releases é semver-only (`vX.Y.Z`)
- semântica de checkpoint/idempotência/retry é preservada
- artefatos de execução são sempre gerados em workdir com timestamp

## Artefatos

Cada execução escreve em:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Arquivos principais:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

Detalhes do `summary.json`:

- `schema_version: 2`
- `command` com subcomando executado (`migrate`, `resume`, `demo`)
- `retry_command` gerado com `gfrm resume` quando houver falhas

## Exit Codes

- `0`: execução bem-sucedida
- não-zero: falha de validação ou operacional
