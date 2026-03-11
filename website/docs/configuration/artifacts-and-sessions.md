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

## Session files

By default, resumable state is saved under `./sessions/last-session.json` unless a custom `--session-file` is used.

Use `gfrm resume` to continue incomplete work. Do not re-run `migrate` just to recover a partial execution.
