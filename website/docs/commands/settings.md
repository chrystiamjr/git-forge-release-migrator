---
sidebar_position: 4
title: settings
---

Manage persisted token and profile configuration.

## Syntax

```bash
gfrm settings <action> [options]
```

## Actions

- `init`
- `set-token-env`
- `set-token-plain`
- `unset-token`
- `show`

## Examples

```bash
gfrm settings init --profile work
gfrm settings set-token-env --provider github --env-name GITHUB_TOKEN --profile work
gfrm settings set-token-plain --provider gitlab --profile work
gfrm settings unset-token --provider github --profile work
gfrm settings show --profile work
```

## Notes

- effective settings are `deep-merge(global, local)`
- `settings show` masks plain tokens
- use `token_env` when possible
