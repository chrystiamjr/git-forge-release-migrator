---
sidebar_position: 4
title: Artifacts and Sessions
---

Each run writes artifacts under a timestamped work directory:

```text
migration-results/<timestamp>/
```

Required artifacts:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

## `summary.json`

Expectations:

- schema version `2`
- executed command metadata
- retry command when failures exist

Common fields to inspect during triage:

- `retry_command` to continue the run with `gfrm resume`
- tag and release counters to see whether the run stopped before or after publication started
- failure metadata and messages that explain blocking validation or partial execution states

When the target forge is missing commit history required for pending tags, `summary.json` records the preflight
failure and should be read together with `failed-tags.txt`.

## Session files

By default, resumable state is saved under `./sessions/last-session.json` unless a custom `--session-file` is used.

Use `gfrm resume` to continue incomplete work. Do not re-run `migrate` just to recover a partial execution.
If you need to diagnose why a retry cannot proceed yet, inspect the session file alongside `summary.json` and
`migration-log.jsonl`.
