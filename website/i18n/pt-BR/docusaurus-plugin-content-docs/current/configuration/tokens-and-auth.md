---
sidebar_position: 2
title: Tokens e Autenticação
---

## Modelo de autenticação por provider

- GitHub: `Authorization: Bearer <token>`
- GitLab: `PRIVATE-TOKEN: <token>`
- Bitbucket Cloud: `Authorization: Bearer <token>`

O `gfrm` nunca registra tokens brutos em logs.

:::caution Tipo de token do Bitbucket
O fluxo Bearer acima funciona com **Repository Access Tokens** ou **Workspace Access Tokens** (gerados em *Repository settings → Access tokens* ou *Workspace settings → Access tokens*).

**API tokens** da conta Atlassian (criados em `id.atlassian.com`) retornam `401 Token is invalid, expired, or not supported for this endpoint` na REST do Bitbucket com Bearer — eles usam um esquema Basic-auth atrelado ao seu email Atlassian e não são suportados pelo `gfrm`. Use um repository ou workspace access token.

A mesma restrição vale para **App Passwords** legados: o `gfrm` não configura Basic auth, então também retornarão 401.
:::

## Opções de armazenamento

### `token_env`

Armazena o nome de uma variável de ambiente e resolve o segredo em runtime.

```yaml
github:
  token_env: GITHUB_TOKEN
```

Esta é a abordagem recomendada.

### `token_plain`

Armazena o token diretamente no arquivo de settings.

```yaml
github:
  token_plain: ghp-xxxxxxxxxxxx
```

Use apenas quando referência por ambiente não for prática.

## Precedência de tokens

### `migrate`

1. token em settings (`token_env`, depois `token_plain`)
2. aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)

### `resume`

1. contexto de token da sessão
2. token em settings (`token_env`, depois `token_plain`)
3. aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)

As flags legadas ocultas `--source-token` e `--target-token` ainda existem como override de compatibilidade, mas não fazem parte do fluxo público recomendado.
