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

## Pares Suportados

Pares cross-forge suportados atualmente:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> github` (Bitbucket Cloud)
- `gitlab -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> gitlab` (Bitbucket Cloud)

Não suportado nesta fase:

- pares same-provider (`github->github`, `gitlab->gitlab`, `bitbucket->bitbucket`)
- hosts Bitbucket Data Center / Server

## Receitas de Comando

```bash
# GitLab -> GitHub
./bin/repo-migrator.py --non-interactive \
  --source-provider gitlab --source-url "https://gitlab.com/group/project" --source-token "<gitlab_token>" \
  --target-provider github --target-url "https://github.com/org/repo" --target-token "<github_token>"

# GitHub -> GitLab
./bin/repo-migrator.py --non-interactive \
  --source-provider github --source-url "https://github.com/org/repo" --source-token "<github_token>" \
  --target-provider gitlab --target-url "https://gitlab.com/group/project" --target-token "<gitlab_token>"

# GitHub -> Bitbucket Cloud
./bin/repo-migrator.py --non-interactive \
  --source-provider github --source-url "https://github.com/org/repo" --source-token "<github_token>" \
  --target-provider bitbucket --target-url "https://bitbucket.org/workspace/repo" --target-token "<bitbucket_bearer>"

# Bitbucket Cloud -> GitLab
./bin/repo-migrator.py --non-interactive \
  --source-provider bitbucket --source-url "https://bitbucket.org/workspace/repo" --source-token "<bitbucket_bearer>" \
  --target-provider gitlab --target-url "https://gitlab.com/group/project" --target-token "<gitlab_token>"

# Dry-run com faixa explícita de tags
./bin/repo-migrator.py --non-interactive --dry-run \
  --source-provider gitlab --source-url "https://gitlab.com/group/project" --source-token "<gitlab_token>" \
  --target-provider bitbucket --target-url "https://bitbucket.org/workspace/repo" --target-token "<bitbucket_bearer>" \
  --from-tag v1.0.0 --to-tag v2.0.0
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

## Seleção e Ordenação de Tags

- O engine atualmente seleciona tags no formato `vX.Y.Z`.
- A ordem de processamento é semver ascendente.
- `--from-tag` e `--to-tag` são inclusivos.
- `--tags-file` atua como filtro adicional após descoberta no provider.

## Notas de Comportamento por Provider

- Auth em GitHub usa override de token em runtime:

```bash
GH_TOKEN="<token>" gh ...
```

- Auth em GitLab usa header `PRIVATE-TOKEN`.
- Auth em Bitbucket nesta fase usa:

```text
Authorization: Bearer <token>
```

- Escopo de URL Bitbucket nesta fase:

```text
https://bitbucket.org/<workspace>/<repo>
```

## Modelo de Manifesto no Bitbucket

Estado de release em Bitbucket é rastreado em Downloads via:

```text
.gfrm-release-<tag>.json
```

Função do manifesto:

- permitir retries idempotentes em fluxos `-> bitbucket`
- indicar se assets estão completos ou pendentes
- carregar metadados normalizados usados em fluxos `bitbucket -> *`

Formato típico:

```json
{
  "version": 1,
  "tag_name": "v1.2.3",
  "release_name": "Release v1.2.3",
  "notes_hash": "<sha256>",
  "uploaded_assets": [
    {"name": "app.zip", "url": "https://...", "type": "package"}
  ],
  "missing_assets": [],
  "updated_at": "2026-01-01T00:00:00Z"
}
```

Comportamento legado (tag de origem Bitbucket sem manifesto):

- migração continua
- notas e rastreabilidade são preservadas
- assets binários podem estar ausentes

## Semântica de Idempotência e Retry

- Tags são migradas antes de releases.
- Arquivo de checkpoint guarda status terminal por chave de tag/release.
- Releases completas no destino são ignoradas.
- Releases incompletas no destino são retomadas.
- `failed-tags.txt` sempre é gerado e pode ser usado para retry direcionado.

## Artefatos de Saída

Cada execução cria:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Arquivos principais:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

Quando há falhas, `summary.json` inclui um comando de retry apenas para tags com erro.

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

## Códigos de Saída

- `0`: migração concluída sem falhas
- `1`: ocorreu pelo menos uma falha
