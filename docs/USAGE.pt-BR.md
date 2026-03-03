# Referência da CLI (Português)

## Comando Canônico

```bash
./bin/repo-migrator.py \
  --source-provider <github|gitlab|bitbucket> \
  --source-url <url> \
  --source-token <token> \
  --target-provider <github|gitlab|bitbucket> \
  --target-url <url> \
  --target-token <token>
```

## Referência Completa de Opções

- `--source-provider <github|gitlab|bitbucket>`
- `--source-url <url>`
- `--source-token <token>`
- `--target-provider <github|gitlab|bitbucket>`
- `--target-url <url>`
- `--target-token <token>`
- `--skip-tags`
- `--from-tag <tag>`
- `--to-tag <tag>`
- `--workdir <dir>` (padrão: `./migration-results`)
- `--log-file <path>`
- `--dry-run`
- `--download-workers <n>` (padrão: `4`, máximo: `16`)
- `--release-workers <n>` (padrão: `1`, máximo: `8`)
- `--checkpoint-file <path>` (padrão: `<results-root>/checkpoints/state.jsonl`)
- `--tags-file <path>` (uma tag por linha)
- `--non-interactive`
- `--no-banner`
- `--quiet`
- `--json`
- `--progress-bar`
- `--help`
- `--load-session`
- `--save-session` (habilitado por padrão)
- `--no-save-session`
- `--resume-session`
- `--session-file <path>`
- `--session-token-mode <env|plain>` (padrão: `env`)
- `--session-source-token-env <env_name>` (padrão: `GFRM_SOURCE_TOKEN`)
- `--session-target-token-env <env_name>` (padrão: `GFRM_TARGET_TOKEN`)
- `--demo-mode`
- `--demo-releases <n>`
- `--demo-sleep-seconds <seconds>`

## Persistência de Sessão

Padrões:

- arquivo de sessão: `./sessions/last-session.json`
- modo de token: `env`

Comandos:

```bash
./bin/repo-migrator.py --resume-session
./bin/repo-migrator.py --load-session --session-file ./sessions/custom.json
./bin/repo-migrator.py --no-save-session
```

Aviso: `--session-token-mode plain` grava tokens em texto puro.

## Artefatos de Saída

Cada execução cria:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Arquivos principais:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

Quando há falhas, `summary.json` inclui um comando de retry apenas das tags com erro.

## Códigos de Saída

- `0`: migração concluída sem falhas
- `1`: ocorreu pelo menos uma falha

## Notas sobre Providers

- Suportado agora: `gitlab -> github`, `github -> gitlab`
- Qualquer par com `bitbucket` retorna erro explícito de não implementado

## Comportamento de Auth no GitHub

Para operações com GitHub, os comandos usam override de token em runtime:

```bash
GH_TOKEN="<target_token>" gh ...
```
