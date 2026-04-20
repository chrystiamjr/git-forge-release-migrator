---
sidebar_position: 2
title: resume
---

Resume a migration from saved session state.

## Syntax

```bash
gfrm resume [options]
```

## Main options

- `--session-file <path>`
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
- `--no-banner`
- `--quiet`
- `--json`

## Token resolution order

1. Session token context
2. Settings token (`token_env`, then `token_plain`)
3. Environment aliases (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, provider aliases)

## Example

```bash
gfrm resume --session-file ./sessions/last-session.json
```

If the default session file does not exist, start a new `migrate` run instead.

## Help and startup checks

- `gfrm resume --help` prints resume-specific usage and options.
- The ASCII banner is reserved for `gfrm` and `gfrm --help`.
- Before resuming tag work, `gfrm resume` verifies that the target forge already contains the commit object referenced by each remaining source tag.
- If required commit history is missing, the command exits early with remediation guidance, including mirror/helper-branch Git snippets and platform-native suggestions for GitHub, GitLab, or Bitbucket.
- `--skip-tags` requires the target forge to already have existing tags; this constraint is validated at runtime and will block migration if violated.
- `--skip-releases` resumes tag migration only and skips release creation/update.
- `--skip-release-assets` resumes release creation/update without downloading or uploading release assets.
