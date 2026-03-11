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

When failures exist, `summary.json` includes a `retry_command` that already uses `gfrm resume`.
