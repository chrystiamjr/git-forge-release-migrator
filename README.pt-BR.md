# Git Forge Release Migrator (gfrm)

[![License](https://img.shields.io/badge/license-MIT-green)](#)
[![Release](https://img.shields.io/badge/release-semantic--release-informational)](./release.config.cjs)
[![Dart SDK](https://img.shields.io/badge/Dart%20SDK-3.41.0-0175C2?logo=dart&logoColor=white)](https://dart.dev/)

`gfrm` é uma CLI em Dart para migrar **tags + releases + notas de release + artefatos** entre plataformas Git.

O runtime principal agora é **100% Dart**. O runtime e os testes em Python foram removidos do fluxo padrão.

## Documentação

- Referência completa da CLI (EN): [docs/USAGE.md](docs/USAGE.md)
- Referência completa da CLI (PT-BR): [docs/USAGE.pt-BR.md](docs/USAGE.pt-BR.md)
- README em inglês: [README.md](README.md)
- Guia do pacote/runtime Dart: [dart_cli/README.md](dart_cli/README.md)
- Contexto para agentes/contribuidores: [AGENTS.md](AGENTS.md)

## Matriz de Suporte

Pares cross-forge suportados:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> github` (Bitbucket Cloud)
- `gitlab -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> gitlab` (Bitbucket Cloud)

Não suportado nesta fase:

- migração same-provider (`github->github`, `gitlab->gitlab`, `bitbucket->bitbucket`)
- Bitbucket Data Center / Server

## Requisitos

- SDK fixado em `3.41.0` via `.fvmrc`
- `fvm` disponível para gestão de SDK
- Tokens válidos para source/target providers

## Início Rápido

```bash
# 1) Instalar tooling local e hooks
yarn install
yarn prepare

# 2) Ativar SDK do projeto via FVM
fvm use 3.41.0

# 3) Instalar dependências Dart
cd dart_cli
fvm dart pub get
cd ..

# 4) Rodar validações locais (fluxo recomendado com yarn)
yarn lint:dart
yarn test:dart

# 5) Exibir ajuda da CLI
./bin/gfrm --help
```

Se o `dart` do shell não estiver vinculado ao FVM globalmente, execute direto com:

```bash
fvm dart run dart_cli/bin/gfrm_dart.dart --help
```

## Visão Geral de Comandos

- `gfrm migrate`: inicia migração com parâmetros explícitos de source/target
- `gfrm resume`: retoma uma migração com sessão salva
- `gfrm demo`: fluxo de simulação local
- `gfrm setup`: bootstrap interativo para perfil de settings
- `gfrm settings`: gerenciamento de tokens/perfis

## Exemplos de Migração

Executar migração com tokens explícitos:

```bash
./bin/gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --source-token "<gitlab_token>" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --target-token "<github_token>" \
  --from-tag v1.0.0 \
  --to-tag v2.0.0
```

Retomar por sessão (arquivo padrão é `./sessions/last-session.json` quando omitido):

```bash
./bin/gfrm resume --session-file ./sessions/last-session.json
```

Inicializar settings quando o projeto ainda não tem configuração:

```bash
./bin/gfrm setup
```

## Perfis de Settings

Comandos de settings:

```bash
./bin/gfrm settings init [--profile <nome>] [--local] [--yes]
./bin/gfrm settings set-token-env --provider <github|gitlab|bitbucket> --env-name <ENV_NAME> [--profile <nome>] [--local]
./bin/gfrm settings set-token-plain --provider <github|gitlab|bitbucket> [--token <valor>] [--profile <nome>] [--local]
./bin/gfrm settings unset-token --provider <github|gitlab|bitbucket> [--profile <nome>] [--local]
./bin/gfrm settings show [--profile <nome>]
```

Arquivos de settings:

- global: `~/.config/gfrm/settings.yaml` (ou `XDG_CONFIG_HOME/gfrm/settings.yaml`)
- override local: `./.gfrm/settings.yaml`

Ordem de resolução de perfil:

1. `--settings-profile`
2. `defaults.profile` em settings
3. `default`

Ordem de resolução de token (`migrate` e `resume`):

1. token explícito na CLI (`--source-token`/`--target-token`)
2. contexto de token da sessão (resume)
3. token do provider em settings (`token_env`, depois `token_plain`)
4. aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)

## Artefatos e Retry

Cada execução escreve em:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Artefatos:

- `migration-log.jsonl`
- `summary.json` (schema v2, inclui `schema_version` e comando executado)
- `failed-tags.txt`

Quando existem falhas, `summary.json` inclui `retry_command` usando `gfrm resume`.

## Fluxo de Desenvolvimento

```bash
# gates locais de qualidade (recomendado)
yarn lint:dart
yarn test:dart

# smoke opcional
./scripts/smoke-test.sh
```

Comandos Dart diretos continuam disponíveis, mas o fluxo diário recomendado é via scripts `yarn`.

Hooks Husky:

- `pre-commit`: `dart format -l 120 --set-exit-if-changed` + `dart analyze`
- `pre-push`: `dart test`

Organização dos testes:

- `dart_cli/test/unit/**`
- `dart_cli/test/feature/**`
- `dart_cli/test/integration/**`

## Release

CI/release é Dart-only com gates de format/analyze/test.

- CI: [.github/workflows/ci.yml](.github/workflows/ci.yml)
- Artefatos (`gfrm` para macOS/Linux/Windows): [.github/workflows/dart-cli-build.yml](.github/workflows/dart-cli-build.yml)
- Semantic release: [.github/workflows/release.yml](.github/workflows/release.yml)

Nomes dos artefatos de build:

- `gfrm-macos` contendo binário `gfrm`
- `gfrm-linux` contendo binário `gfrm`
- `gfrm-windows` contendo binário `gfrm.exe`

Observações de primeira execução por plataforma:

- macOS: se o Gatekeeper bloquear um binário baixado sem assinatura, execute `xattr -d com.apple.quarantine ./gfrm`
- Linux: garanta permissão de execução com `chmod +x ./gfrm`
- Windows: binários sem assinatura podem acionar alerta do SmartScreen até configurar code signing
