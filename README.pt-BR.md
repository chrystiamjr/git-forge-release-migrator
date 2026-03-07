# Git Forge Release Migrator (gfrm)

[![Python](https://img.shields.io/badge/python-3.9%2B-blue)](https://www.python.org/)
[![Licença](https://img.shields.io/badge/license-MIT-green)](#)
[![Release](https://img.shields.io/badge/release-semantic--release-informational)](./release.config.cjs)

CLI em Python para migrar **tags + releases + notas de release + artefatos** entre plataformas Git.

Projetado para reexecução segura: itens concluídos são ignorados, itens incompletos são retomados e cada execução gera saída estruturada para auditoria e retry.

## Documentação

- Referência completa da CLI: [docs/USAGE.pt-BR.md](docs/USAGE.pt-BR.md)
- Referência da CLI em inglês: [docs/USAGE.md](docs/USAGE.md)
- README em inglês: [README.md](README.md)
- Guia para agentes de IA: [AGENTS.md](AGENTS.md)

## Conteúdo

- [Matriz de Suporte](#matriz-de-suporte)
- [Modelo dos Providers](#modelo-dos-providers)
- [Contrato de Manifesto no Bitbucket](#contrato-de-manifesto-no-bitbucket)
- [Requisitos](#requisitos)
- [Início Rápido](#início-rápido)
- [Receitas de Comando](#receitas-de-comando)
- [Perfis de Settings](#perfis-de-settings)
- [Regras de Seleção de Tags](#regras-de-seleção-de-tags)
- [Saída, Retry e Sessões](#saída-retry-e-sessões)
- [Modelo de Segurança](#modelo-de-segurança)
- [Troubleshooting](#troubleshooting)
- [Setup para Desenvolvimento](#setup-para-desenvolvimento)
- [Processo de Release (deste projeto)](#processo-de-release-deste-projeto)

## Matriz de Suporte

| Origem | Destino | Status |
|---|---|---|
| `gitlab` | `github` | Disponível |
| `github` | `gitlab` | Disponível |
| `github` | `bitbucket` | Disponível (Bitbucket Cloud) |
| `bitbucket` | `github` | Disponível (Bitbucket Cloud) |
| `gitlab` | `bitbucket` | Disponível (Bitbucket Cloud) |
| `bitbucket` | `gitlab` | Disponível (Bitbucket Cloud) |

Observações:

- Migrações para o mesmo provider seguem fora de escopo nesta fase (`github->github`, `gitlab->gitlab`, `bitbucket->bitbucket`).
- O suporte a Bitbucket nesta fase é **somente Bitbucket Cloud** (`bitbucket.org`).

## Modelo dos Providers

- `gitlab`: release GitLab + links + sources.
- `github`: release GitHub + assets + source archives automáticos.
- `bitbucket` neste projeto: **tag + mensagem da tag + arquivos em Downloads**.

Ou seja, no Bitbucket a noção de "release" é sintetizada com base em tag e artefatos de download.

## Contrato de Manifesto no Bitbucket

Para destinos Bitbucket, cada tag migrada grava um manifesto em Downloads:

- nome do arquivo: `.gfrm-release-<tag>.json`
- finalidade: idempotência e decisão de retry/skip
- campos mínimos:
  - `version`
  - `tag_name`
  - `release_name`
  - `notes_hash`
  - `uploaded_assets`
  - `missing_assets`
  - `updated_at`

Comportamento em tags legadas do Bitbucket sem manifesto:

- a migração continua (notas + link de rastreabilidade)
- assets podem ficar vazios
- a ausência do manifesto por si só não falha a migração

## Requisitos

| Dependência | Versão | Observação |
|---|---|---|
| Python | `>=3.9` | Necessário para executar a CLI |
| `curl` | qualquer | Usado para chamadas de API e transferência de artefatos |
| `gh` (GitHub CLI) | qualquer | Necessário apenas quando o fluxo envolve GitHub |

Instalar o `gh`: https://cli.github.com

## Início Rápido

1. Instalação:

```bash
pip install -e .
```

2. Executar modo interativo:

```bash
./bin/repo-migrator.py
```

3. Executar modo não interativo:

```bash
./bin/repo-migrator.py \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --source-token "<gitlab_token>" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --target-token "<github_token>" \
  --from-tag v3.2.1 \
  --to-tag v3.40.0
```

## Receitas de Comando

```bash
# Interativo (recomendado na primeira execução)
./bin/repo-migrator.py

# Bootstrap de settings (recomendado)
./bin/repo-migrator.py settings init

# Retomar última sessão
./bin/repo-migrator.py --resume-session

# Somente dry-run (GitLab -> GitHub)
./bin/repo-migrator.py --dry-run \
  --source-provider gitlab --source-url "https://gitlab.com/group/project" --source-token "<gitlab_token>" \
  --target-provider github --target-url "https://github.com/org/repo" --target-token "<github_token>"

# GitHub -> Bitbucket Cloud
./bin/repo-migrator.py --non-interactive \
  --source-provider github --source-url "https://github.com/org/repo" --source-token "<github_token>" \
  --target-provider bitbucket --target-url "https://bitbucket.org/workspace/repo" --target-token "<bitbucket_bearer>"

# Bitbucket Cloud -> GitLab
./bin/repo-migrator.py --non-interactive \
  --source-provider bitbucket --source-url "https://bitbucket.org/workspace/repo" --source-token "<bitbucket_bearer>" \
  --target-provider gitlab --target-url "https://gitlab.com/group/project" --target-token "<gitlab_token>"

# Reexecutar somente tags com falha da execução anterior
./bin/repo-migrator.py --resume-session --tags-file ./migration-results/<run>/failed-tags.txt
```

## Perfis de Settings

O sistema de `settings` evita pedir token em toda execução.

### Estrutura de Arquivos e Merge

Os settings são carregados de dois arquivos:

- global: `~/.config/gfrm/settings.yaml`
- override local: `./.gfrm/settings.yaml`

Estratégia de carga:

1. lê arquivo global (se existir)
2. lê arquivo local (se existir)
3. aplica merge profundo com local sobre global

Ou seja: o local sobrescreve apenas chaves iguais, mantendo o restante do global.

### Regras de Seleção de Perfil

A escolha do perfil efetivo segue:

1. `--settings-profile <nome>` no comando de execução
2. `defaults.profile` no merge final
3. `default`

Como trocar perfil em runtime:

```bash
./bin/repo-migrator.py --settings-profile work ...
./bin/repo-migrator.py --settings-profile personal ...
```

Como mudar o perfil padrão:

- editar `defaults.profile` no YAML
- ou sempre informar `--settings-profile`

### Formato YAML (v1)

```yaml
version: 1
defaults:
  profile: work
profiles:
  work:
    providers:
      github:
        token_env: GH_WORK_TOKEN
      gitlab:
        token_env: GL_WORK_TOKEN
  personal:
    providers:
      github:
        token_env: GH_PERSONAL_TOKEN
      bitbucket:
        token_plain: bbp_exemplo_token_plain
```

Campos de provider:

- `token_env`: preferido e mais seguro, referencia nome de variável de ambiente
- `token_plain`: opcional e explícito, token em texto puro

Se ambos existirem, `token_env` é tentado primeiro.

### Comandos de Settings

```bash
./bin/repo-migrator.py settings init [--profile <nome>] [--local] [--yes]
./bin/repo-migrator.py settings set-token-env --provider <github|gitlab|bitbucket> --env-name <ENV_NAME> [--profile <nome>] [--local]
./bin/repo-migrator.py settings set-token-plain --provider <github|gitlab|bitbucket> [--token <valor>] [--profile <nome>] [--local]
./bin/repo-migrator.py settings unset-token --provider <github|gitlab|bitbucket> [--profile <nome>] [--local]
./bin/repo-migrator.py settings show [--profile <nome>]
```

Observações:

- `--local` grava em `./.gfrm/settings.yaml`; sem `--local`, grava no global.
- sem `--profile`, o comando usa a mesma lógica de perfil efetivo.
- `settings show` exibe merge efetivo e mascara `token_plain`.
- `settings init` faz apenas leitura de `~/.zshrc`, `~/.zprofile`, `~/.bashrc` e `~/.bash_profile` para sugerir nomes de variáveis.
- `settings init` não define `token_plain`; para isso use `settings set-token-plain`.

### Fluxo Recomendado com Perfis

1. Inicializar settings locais do projeto:
```bash
./bin/repo-migrator.py settings init --local
```
2. Criar/ajustar perfil dedicado:
```bash
./bin/repo-migrator.py settings set-token-env --provider github --env-name GH_WORK_TOKEN --profile work --local
./bin/repo-migrator.py settings set-token-env --provider gitlab --env-name GL_WORK_TOKEN --profile work --local
```
3. Executar migração usando esse perfil:
```bash
./bin/repo-migrator.py --settings-profile work --source-provider github --target-provider gitlab ...
```

### Ordem de Resolução de Token em Runtime

Para cada lado (`source` e `target`), a ordem é:

1. argumentos CLI: `--source-token` / `--target-token`
2. valores carregados da sessão (`--load-session` / `--resume-session`)
3. settings do provider no perfil efetivo:
   - `token_env` (via `os.getenv`)
   - `token_plain`
4. fallback de ambiente:
   - `GFRM_SOURCE_TOKEN` / `GFRM_TARGET_TOKEN`
   - GitHub: `GITHUB_TOKEN`, `GH_TOKEN`, `GH_PERSONAL_TOKEN`
   - GitLab: `GITLAB_TOKEN`, `GL_TOKEN`
   - Bitbucket: `BITBUCKET_TOKEN`, `BB_TOKEN`
5. prompt interativo (apenas modo interativo)

## Regras de Seleção de Tags

- O engine atualmente seleciona tags no formato semântico `vX.Y.Z`.
- `--from-tag` e `--to-tag` são inclusivos.
- `--tags-file` funciona como filtro adicional sobre as releases descobertas no provider.

## Saída, Retry e Sessões

Cada execução grava em:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Arquivos gerados:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

Padrões de sessão:

- arquivo de sessão: `./sessions/last-session.json`
- modo de token: `env` (recomendado; não grava token em texto puro)

## Modelo de Segurança

- Migração de tags ocorre antes da migração de releases.
- Release completa já existente é ignorada.
- Release incompleta existente é retomada/atualizada.
- Checkpoints evitam reprocessamento de estados terminais.
- Tokens nunca são impressos em log.

Para operações com GitHub, comandos são executados com override de token em runtime:

```bash
GH_TOKEN="<target_token>" gh ...
```

Para operações com Bitbucket nesta fase, o auth esperado é:

```text
Authorization: Bearer <token>
```

## Troubleshooting

- `gh: Bad credentials (HTTP 401)` com `--dry-run`:
  - O dry-run ainda valida estado de release no destino, então o token de destino precisa ser válido.
- `Only Bitbucket Cloud URLs are supported in this phase`:
  - Use `https://bitbucket.org/<workspace>/<repo>`.
- `pip install -e .[dev]` falha no `zsh`:
  - Use aspas: `pip install -e '.[dev]'`.

## Setup para Desenvolvimento

```bash
pip install -e '.[dev]'
./scripts/install-hooks.sh
```

Hooks configurados:

- `pre-commit`: lint + verificação de formatação
- `commit-msg`: validação de mensagem com Commitizen
- `pre-push`: suíte completa de testes

Rodar testes manualmente:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

## Processo de Release (deste projeto)

Este repositório usa `semantic-release` + GitHub Actions na branch `main`.

- Conventional Commits definem o bump de versão.
- Nova tag `vX.Y.Z` é criada automaticamente.
- GitHub Release e changelog são gerados.

Veja: [CHANGELOG.md](CHANGELOG.md), [release.config.cjs](release.config.cjs), [.github/workflows/release.yml](.github/workflows/release.yml)
