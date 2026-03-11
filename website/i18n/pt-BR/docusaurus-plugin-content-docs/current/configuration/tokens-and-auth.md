---
sidebar_position: 2
title: Tokens e Autenticação
---

## Modelo de autenticação por provider

- GitHub: `Authorization: Bearer <token>`
- GitLab: `PRIVATE-TOKEN: <token>`
- Bitbucket Cloud: `Authorization: Bearer <token>`

O `gfrm` nunca registra tokens brutos em logs.

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
