---
sidebar_position: 2
title: Resume and Retry
---

Use `gfrm resume` whenever a run is interrupted or partially failed.

## Standard resume

```bash
gfrm resume
```

## Explicit session file

```bash
gfrm resume --session-file ./sessions/last-session.json
```

## What gets skipped

- completed items remain completed
- terminal checkpoint states prevent duplicate work
- incomplete items are retried

## Failure triage

Inspect:

- `failed-tags.txt`
- `summary.json`
- `migration-log.jsonl`

When failures exist, `summary.json` includes a `retry_command` that already uses `gfrm resume`. Treat that command and
the written artifacts as the authoritative retry path, even when runtime completion or failure events are also
available to internal consumers.

## Missing target history

If `resume` or `migrate` stops before tag creation because the target forge does not contain the commit object
referenced by a source tag:

- read the preflight hint in `summary.json`
- inspect `failed-tags.txt` to see which tags were blocked
- inspect `migration-log.jsonl` when you need step-by-step execution context
- align repository history before retrying

Safe remediation patterns:

- mirror the source repository into the target when the target can accept the full history
- push a helper branch that carries the missing commit objects when you must preserve the current default branch
- use `--skip-tags` only when the requested tags already exist in the target forge
