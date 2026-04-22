---
sidebar_position: 5
title: Testes Smoke
---

Este guia mostra passo a passo como configurar e rodar um smoke test real end-to-end do `gfrm` contra seus próprios repositórios de teste descartáveis em GitHub, GitLab e Bitbucket. O smoke test verifica que o binário executa de verdade um round-trip de migração: releases falsos criados na origem, migrados para o destino, artefatos validados, origem limpa.

## O que smoke testing cobre aqui

- **Não** são testes unitários (rode `dart test` em `dart_cli/`).
- **Não** é o fluxo local `demo --dry-run` (zero I/O real contra forges).
- **É**: binário + forge de origem real + forge de destino real + seus tokens pessoais + repositórios de teste descartáveis que você controla.

Cada execução leva de 1 a 3 minutos por par de forge e consome um punhado de requests à API dos forges.

## Pré-requisitos

- Binário `gfrm` instalado. Veja [instruções de instalação](../getting-started/install-and-verify.md).
- Contas em pelo menos dois forges (GitHub, GitLab ou Bitbucket Cloud — qualquer par serve).
- Permissão para criar um repositório privado em cada forge.

## 1. Crie repositórios de teste

Crie um repositório privado vazio em cada forge que você quer testar. Sugestão de nome: `gfrm-test-source` e `gfrm-test-target` para a intenção ficar óbvia. Crie apenas os repositórios necessários para o par que você vai exercitar.

| Forge | Criar em |
|---|---|
| GitHub | https://github.com/new |
| GitLab | https://gitlab.com/projects/new |
| Bitbucket Cloud | https://bitbucket.org/repo/create |

Mantenha todos os repositórios de teste **privados** e **vazios** (sem README, sem license). Os workflows de fixture inicializam o que precisam.

:::note Bitbucket exige um workspace
Diferente de GitHub e GitLab, repositórios no Bitbucket Cloud precisam morar dentro de um **workspace** — não dá pra criar repositório direto na conta pessoal. Se você ainda não tem um, crie em https://bitbucket.org/account/workspaces/ antes de usar o formulário de criação de repo. O slug do workspace é o segmento `{workspace}` em URLs como `https://bitbucket.org/{workspace}/{repo}`.

**Pegadinha de plano de workspace:** um workspace do Bitbucket Cloud que excedeu o limite de usuários (comum no plano Free) silenciosamente torna todos os repositórios dentro dele **read-only**, e o push por Git falha com HTTP 402:

```
[ALERT] Your push failed because the account '<workspace>' has exceeded its
[ALERT] user limit and this repository is restricted to read-only access.
```

Se acontecer, remova membros inativos ou faça upgrade de plano em `https://bitbucket.org/<workspace>/workspace/settings/plans`, ou escolha outro workspace com write habilitado. O `gfrm smoke` só consegue popular e limpar fixtures quando pushes são aceitos.

**Criar um workspace novo** como alternativa não é mais uma ação simples pela UI. O Bitbucket removeu a opção "Create workspace" — o dropdown `+ Create` só oferece Repository/Project/Package/Snippet, e `https://bitbucket.org/workspaces/create` devolve "Repository not found". Workspaces novos agora são provisionados criando uma nova **organização** Atlassian em `https://admin.atlassian.com/` e adicionando o produto Bitbucket nela. Planeje de acordo antes de escolher o Bitbucket como forge de smoke.
:::

## 2. Instale os workflows de fixture

Copie os arquivos de workflow deste repositório para cada um dos seus repositórios de teste.

### GitHub

De `docs/smoke-tests/workflows/github/` copie os dois arquivos para `.github/workflows/` no repo de teste:

- [`create-fake-releases.example.yml`](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/smoke-tests/workflows/github/create-fake-releases.example.yml) → `.github/workflows/create-fake-releases.yml`
- [`cleanup-tags-and-releases.example.yml`](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/smoke-tests/workflows/github/cleanup-tags-and-releases.example.yml) → `.github/workflows/cleanup-tags-and-releases.yml`

Commit e push no branch padrão.

### GitLab

De `docs/smoke-tests/workflows/gitlab/` copie:

- [`gitlab-ci.example.yml`](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/smoke-tests/workflows/gitlab/gitlab-ci.example.yml) → `.gitlab-ci.yml` na raiz do projeto.

O arquivo define os dois jobs manuais `create_fake_releases` e `cleanup_tags_and_releases`.

Adicione uma variável de CI/CD **mascarada** no projeto de teste:

- Nome: `GITLAB_PERSONAL_TOKEN`
- Valor: seu personal access token (veja seção 3)
- Mascarada: sim
- Protegida: não (para ficar disponível em jobs manuais de qualquer branch)

Commit e push.

### Bitbucket Cloud

De `docs/smoke-tests/workflows/bitbucket/` copie:

- [`bitbucket-pipelines.example.yml`](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/smoke-tests/workflows/bitbucket/bitbucket-pipelines.example.yml) → `bitbucket-pipelines.yml` na raiz do repo.

Habilite Pipelines no repo: Repository settings → Pipelines → Settings → Enable.

Adicione uma variável **Secured** no repo:

- Nome: `BITBUCKET_TOKEN`
- Valor: Repository Access Token (veja seção 3)
- Secured: sim

Commit e push.

## 3. Gere tokens pessoais

Você precisa de um token por forge que vai participar do smoke test.

### Token pessoal GitHub

Escopos mínimos verificados em 2026-04-20:

- `repo` — ler + criar tags, releases e assets no repo de teste
- `workflow` — disparar os workflows de fixture via API

Gere um PAT classic em https://github.com/settings/tokens/new e marque os dois escopos. Copie o valor e exponha via a env var referenciada em `settings.yaml` (padrão: `GH_TOKEN` ou `GH_PERSONAL_TOKEN`).

Se o GitHub renomear ou dividir esses escopos, confira a lista atual: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#personal-access-tokens-classic

**Alternativa com fine-grained PAT**: restrinja o token ao único repo de teste e conceda:

- Actions: read/write
- Contents: read/write
- Metadata: read (concedido automaticamente)

### Token pessoal GitLab

Escopos mínimos verificados em 2026-04-20:

- `api` — acesso REST completo (necessário para endpoints de release + pipeline)
- `read_repository`, `write_repository` — git push/pull via HTTPS

Gere em https://gitlab.com/-/user_settings/personal_access_tokens. Exponha via a env var referenciada em `settings.yaml` (padrão: `GITLAB_PERSONAL_TOKEN`).

Se o GitLab mudar esses escopos: https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html#personal-access-token-scopes

**Alternativa com project access token**: escopo ao único projeto de teste com role Maintainer e os mesmos `api` + `write_repository`.

### Repository Access Token do Bitbucket

Escopos mínimos verificados em 2026-04-20:

- `repository:admin` — criar/deletar tags e downloads no repo de teste
- `pipeline:write` — disparar pipelines customizados via API
- `pipeline:variable` — se o pipeline de fixture usa variáveis

Gere um Repository Access Token nas settings do repo de teste: **Repository settings → Access tokens → Create access token**.

Se Bitbucket mudar escopos: https://support.atlassian.com/bitbucket-cloud/docs/repository-access-tokens/

:::caution Não reutilize um API token de conta Atlassian
API tokens de conta Atlassian (gerados em `id.atlassian.com`) e App Passwords legados retornam `401 Token is invalid, expired, or not supported for this endpoint` na REST do Bitbucket quando enviados como `Authorization: Bearer …`, que é o esquema que o `gfrm` usa. Gere um Repository Access Token (ou Workspace Access Token) no lugar — são mais estreitos, mais seguros e é o caminho suportado.
:::

## 4. Configure a CLI

Execute o setup inicial:

```bash
gfrm setup
```

Então amarre a env var de cada provider no `settings.yaml`:

```bash
gfrm settings set-token-env --provider github --env-name GH_PERSONAL_TOKEN
gfrm settings set-token-env --provider gitlab --env-name GITLAB_PERSONAL_TOKEN
gfrm settings set-token-env --provider bitbucket --env-name BITBUCKET_TOKEN
```

Confirme:

```bash
gfrm settings show
```

Os valores de token saem mascarados. Você deve ver o nome da env var correta ao lado de cada provider.

## 5. Rode o smoke test

### Round-trip básico

```bash
gfrm smoke \
  --source-provider github --source-url https://github.com/voce/gfrm-test-source \
  --target-provider gitlab --target-url https://gitlab.com/voce/gfrm-test-target
```

Saída esperada:

- `Creating fixture on source ...` seguido de polls até o workflow terminar
- `Cooldown 15s (after setup)`
- As linhas normais da migrate
- `Cooldown 15s (after migration)`
- `Cleaning up source ...`
- Sumário final com hash do commit e caminhos dos artefatos

### Pares comuns

```bash
# GitHub → GitLab (mais comum)
gfrm smoke --source-provider github --source-url <gh-src> --target-provider gitlab --target-url <gl-tgt>

# GitLab → GitHub
gfrm smoke --source-provider gitlab --source-url <gl-src> --target-provider github --target-url <gh-tgt>

# Bitbucket → GitHub
gfrm smoke --source-provider bitbucket --source-url <bb-src> --target-provider github --target-url <gh-tgt>

# Bitbucket → GitLab
gfrm smoke --source-provider bitbucket --source-url <bb-src> --target-provider gitlab --target-url <gl-tgt>

# GitHub → Bitbucket
gfrm smoke --source-provider github --source-url <gh-src> --target-provider bitbucket --target-url <bb-tgt>

# GitLab → Bitbucket
gfrm smoke --source-provider gitlab --source-url <gl-src> --target-provider bitbucket --target-url <bb-tgt>
```

Migrações entre o mesmo provider (ex: GitHub → GitHub) **não** são suportadas.

## 6. Interpretar resultados

Artefatos caem no workdir que você passou (ou num subfolder timestamped de `.tmp/smoke/` por padrão):

- `summary.json` — `schema_version: 2`, `command: "migrate"`, `retry_command` preenchido só em caso de falha parcial.
- `failed-tags.txt` — vazio em run limpo.
- `migration-log.jsonl` — um evento JSON por passo. Útil para post-mortem.

Smoke bem-sucedido sai com código 0. Qualquer exit não-zero com mensagem apontando uma das fases indica algo acionável — veja a referência do comando para os códigos de saída.

## 7. Troubleshooting {#troubleshooting}

### `403 Forbidden` de algum forge

Causa mais comum: o projeto de teste foi flaggeado pela heurística de abuso do forge depois de muitos ciclos create/delete idênticos. Os workflows deste repo mitigam isso com sufixo de timestamp por run, mas um projeto já flaggeado fica bloqueado por um tempo.

Remédios:

1. Valide o token com `GET /user` pra confirmar que o token em si está bom:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" -H "PRIVATE-TOKEN: $GITLAB_PERSONAL_TOKEN" https://gitlab.com/api/v4/user
   ```
   200 → token ok, projeto com rate limit. Espere 12-24h.
2. Rode contra um novo repo de teste com nome diferente.
3. Diminuir o cooldown **não** resolve; aumentar sim. Tente `--cooldown-seconds 30`.

### Workflow de fixture não disparou

- Confirme que o arquivo do workflow está no branch padrão do repo.
- GitHub: confirme que tem `workflow_dispatch` no YAML e que o token tem scope `workflow`.
- GitLab: confirme que as rules do job permitem trigger `web` / `api` e que o token tem scope `api`.
- Bitbucket: confirme que Pipelines está habilitado no repo e que o nome do custom pipeline bate.

### Migração funcionou mas cleanup deu 403

O artefato da migração é autoritativo — inspecione `summary.json`. Depois dispare manualmente o `cleanup-tags-and-releases` (ou equivalente) pela UI do forge para deixar a origem vazia de novo.

### Token sem os scopes necessários

A mensagem de erro geralmente nomeia a permissão faltante. Gere um novo token com os scopes exatos da seção 3. Confira se não escolheu acidentalmente um PAT "fine-grained" limitado a repos que não incluem o de teste.

## 8. Cleanup e reset

Depois de qualquer run (ou em meio de debug):

- `gfrm smoke --skip-setup --skip-teardown ...` roda só a fase de migrate — útil quando você quer re-migrar sem tocar a origem.
- Cleanup manual: dispare o workflow `cleanup-tags-and-releases` direto pela UI do forge.
- Reset completo: apague e recrie o repo de teste. Os arquivos de workflow são pequenos; re-adicioná-los é rápido.
