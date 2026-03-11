---
sidebar_position: 2
title: Tokens and Auth
---

## Provider auth model

- GitHub: `Authorization: Bearer <token>`
- GitLab: `PRIVATE-TOKEN: <token>`
- Bitbucket Cloud: `Authorization: Bearer <token>`

`gfrm` never logs raw tokens.

## Token storage options

### `token_env`

Store the name of an environment variable and resolve the secret at runtime.

```yaml
github:
  token_env: GITHUB_TOKEN
```

This is the recommended approach.

### `token_plain`

Store the token directly in the settings file.

```yaml
github:
  token_plain: ghp-xxxxxxxxxxxx
```

Use this only when an env reference is not practical.

## Token precedence

### `migrate`

1. Settings token (`token_env`, then `token_plain`)
2. Environment aliases (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, provider aliases)

### `resume`

1. Session token context
2. Settings token (`token_env`, then `token_plain`)
3. Environment aliases (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, provider aliases)

Hidden legacy flags `--source-token` and `--target-token` still exist for compatibility overrides, but they are not part
of the recommended public workflow.
