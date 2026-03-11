---
sidebar_position: 1
title: Settings Profiles
---

`gfrm` persists provider configuration in YAML settings files and resolves one active profile per run.

## Settings file locations

| Scope | Path |
| --- | --- |
| Global | `~/.config/gfrm/settings.yaml` or `$XDG_CONFIG_HOME/gfrm/settings.yaml` |
| Local override | `./.gfrm/settings.yaml` |

Effective settings are `deep-merge(global, local)`.

## Example

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

## Profile resolution order

1. Explicit `--settings-profile`
2. `defaults.profile`
3. `default`

## Recommended flow

- Keep one default profile for normal usage.
- Add named profiles for separate organizations or token policies.
- Use local settings only for repo-specific overrides.
