---
sidebar_position: 4
title: settings
---

Gerencia configuração persistente de tokens e perfis.

## Sintaxe

```bash
gfrm settings <ação> [opções]
```

## Ações

- `init`
- `set-token-env`
- `set-token-plain`
- `unset-token`
- `show`

## Exemplos

```bash
gfrm settings init --profile work
gfrm settings set-token-env --provider github --env-name GITHUB_TOKEN --profile work
gfrm settings set-token-plain --provider gitlab --profile work
gfrm settings unset-token --provider github --profile work
gfrm settings show --profile work
```

## Notas

- as settings efetivas usam `deep-merge(global, local)`
- `settings show` mascara tokens plain
- prefira `token_env` quando possível
