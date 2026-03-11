---
sidebar_position: 1
title: Settings Profiles
---

O `gfrm` persiste a configuração dos providers em arquivos YAML e resolve um perfil ativo por execução.

## Localização dos arquivos

| Escopo | Caminho |
| --- | --- |
| Global | `~/.config/gfrm/settings.yaml` ou `$XDG_CONFIG_HOME/gfrm/settings.yaml` |
| Override local | `./.gfrm/settings.yaml` |

As settings efetivas usam `deep-merge(global, local)`.

## Exemplo

```yaml
defaults:
  profile: default

profiles:
  default:
    providers:
      github:
        token_env: GITHUB_TOKEN
      gitlab:
        token_env: GITLAB_TOKEN
  work:
    providers:
      github:
        token_env: WORK_GITHUB_TOKEN
      gitlab:
        token_plain: glpat-xxxxxxxxxxxx
```

## Ordem de resolução do perfil

1. `--settings-profile`
2. `defaults.profile`
3. `default`

## Fluxo recomendado

- mantenha um perfil default para uso normal
- adicione perfis nomeados para organizações ou políticas de token diferentes
- use settings locais apenas para overrides específicos do repositório
