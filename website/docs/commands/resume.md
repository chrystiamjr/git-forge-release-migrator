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
