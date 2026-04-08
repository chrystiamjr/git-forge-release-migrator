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

- `init` — inicializa referências de variáveis de ambiente para tokens dos providers
- `set-token-env` — salva o nome da variável de ambiente que deve resolver o token de um provider
- `set-token-plain` — salva um valor de token plain para um provider
- `unset-token` — remove a configuração de token armazenada para um provider
- `show` — imprime as settings efetivas já mescladas com segredos mascarados

## Exemplos

```bash
gfrm settings init --profile work
gfrm settings set-token-env --provider github --env-name GITHUB_TOKEN --profile work
gfrm settings set-token-plain --provider gitlab --profile work
gfrm settings unset-token --provider github --profile work
gfrm settings show --profile work
```

Exemplos mais práticos:

```bash
# Salve as settings no repositório local em vez do config global
gfrm settings init --profile work --local

# Prefira resolução por variável de ambiente em workstations compartilhadas e CI
gfrm settings set-token-env --provider github --env-name GITHUB_TOKEN --profile work

# Use token plain só quando o gerenciamento por env não estiver disponível
gfrm settings set-token-plain --provider gitlab --profile work
```

## Help e uso por ação

- `gfrm settings --help` mostra o catálogo de ações de `settings`.
- `gfrm settings <ação> --help` mostra uso e opções específicos da ação.
- `gfrm settings init --help` inclui `--profile`, `--local` e `--yes`.
- `gfrm settings set-token-env --help` inclui `--provider`, `--env-name`, `--profile` e `--local`.
- `gfrm settings set-token-plain --help` inclui `--provider`, `--token`, `--profile` e `--local`.
- `gfrm settings unset-token --help` inclui `--provider`, `--profile` e `--local`.
- `gfrm settings show --help` inclui `--profile`.

## Notas

- as settings efetivas usam `deep-merge(global, local)`
- `settings show` mascara tokens plain
- prefira `token_env` quando possível

Exemplo de saída mascarada do `settings show`:

```yaml
profiles:
  work:
    github:
      token_env: GITHUB_TOKEN
    gitlab:
      token_plain: "***"
```
