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

- `init` — bootstrap token env references for providers
- `set-token-env` — store the env var name that should resolve a provider token
- `set-token-plain` — store a plain provider token value
- `unset-token` — remove the stored token configuration for a provider
- `show` — print the effective merged settings with secrets masked

## Examples

```bash
gfrm settings init --profile work
gfrm settings set-token-env --provider github --env-name GITHUB_TOKEN --profile work
gfrm settings set-token-plain --provider gitlab --profile work
gfrm settings unset-token --provider github --profile work
gfrm settings show --profile work
```

More practical examples:

```bash
# Store settings in the local repository instead of the global config
gfrm settings init --profile work --local

# Prefer env-backed token resolution for shared workstations and CI
gfrm settings set-token-env --provider github --env-name GITHUB_TOKEN --profile work

# Use a plain token only when env management is not available
gfrm settings set-token-plain --provider gitlab --profile work
```

## Help and action usage

- `gfrm settings --help` prints the settings action catalog.
- `gfrm settings <action> --help` prints action-specific usage and options.
- `gfrm settings init --help` includes `--profile`, `--local`, and `--yes`.
- `gfrm settings set-token-env --help` includes `--provider`, `--env-name`, `--profile`, and `--local`.
- `gfrm settings set-token-plain --help` includes `--provider`, `--token`, `--profile`, and `--local`.
- `gfrm settings unset-token --help` includes `--provider`, `--profile`, and `--local`.
- `gfrm settings show --help` includes `--profile`.

## Notes

- effective settings are `deep-merge(global, local)`
- `settings show` masks plain tokens
- use `token_env` when possible

Example masked output from `settings show`:

```yaml
profiles:
  work:
    github:
      token_env: GITHUB_TOKEN
    gitlab:
      token_plain: "***"
```
