---
sidebar_position: 1
title: migrate
---

Start a migration from explicit source and target parameters.

## Syntax

```bash
gfrm migrate \
  --source-provider <github|gitlab|bitbucket> \
  --source-url <url> \
  --target-provider <github|gitlab|bitbucket> \
  --target-url <url> \
  [options]
```

## Required flags

- `--source-provider`
- `--source-url`
- `--target-provider`
- `--target-url`

## Main options

- `--settings-profile <name>`
- `--skip-tags`
- `--skip-releases`
- `--skip-release-assets`
- `--from-tag <tag>`
- `--to-tag <tag>`
- `--dry-run`
- `--download-workers <1..16>`
- `--release-workers <1..8>`
- `--workdir <dir>`
- `--session-file <path>`
- `--no-banner`
- `--quiet`
- `--json`

## Validation rules

- source and target providers must differ
- `--download-workers` must be `1..16`
- `--release-workers` must be `1..8`
- if both `--from-tag` and `--to-tag` are present, the semver order must be valid
- `--skip-tags` is only allowed when the target forge already has existing tags

## Migration order and release selection

Migration always proceeds in two phases, regardless of `--skip-*` flags:

1. **Tag phase**: All selected tags migrate before any release work begins
2. **Release phase**: Releases matching semver tags (`vX.Y.Z`) are created/updated after tags complete

**Release selection**: Only tags matching the semver pattern `vX.Y.Z` generate corresponding releases. For example:
- `v1.0.0`, `v2.1.3-rc1` → releases are migrated
- `release-1.0`, `main`, `alpha` → no corresponding release is migrated (tag-only)

This order is mandatory and ensures tags exist before releases are created. To skip either phase, use `--skip-tags` or `--skip-releases`.

## Token sources

1. Settings token (`token_env`, then `token_plain`)
2. Environment aliases (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, provider aliases)

## Example

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --settings-profile default \
  --from-tag v1.0.0 \
  --to-tag v2.0.0
```

## Help and startup checks

- `gfrm migrate --help` prints migrate-specific usage and options.
- The ASCII banner is reserved for `gfrm` and `gfrm --help`.
- Before tag creation, `gfrm migrate` verifies that the target forge already contains the commit object referenced by each source tag that still needs migration.
- If required commit history is missing, the command exits early with remediation guidance, including mirror/helper-branch Git snippets and platform-native suggestions for GitHub, GitLab, or Bitbucket.
- `--skip-tags` requires the target forge to already have existing tags; this constraint is validated at runtime and will block migration if violated.
- `--skip-releases` migrates tags only and skips release creation/update.
- `--skip-release-assets` creates or updates releases without downloading or uploading release assets.
