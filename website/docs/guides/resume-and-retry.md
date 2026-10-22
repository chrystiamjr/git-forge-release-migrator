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

## Retry from desktop Results

**Retry Failed Tags** appears after a retryable failed run when its controller still has the run context,
failed tags, and existing `failed-tags.txt` and checkpoint files. The action stays disabled while the retry is
being submitted. Idle, active, successful, and non-retryable runs do not offer it.

The action uses the shared typed `resume` execution path. It keeps the original repositories, resolved token
context, settings profile, tag range, migration options, worker counts, output root, and checkpoint. Only the
failed tags are selected; completed checkpoint items remain skipped. Progress and Results observe the new run.
The displayed terminal command is not parsed to reconstruct credentials or retry parameters.

Retry context is kept in memory for the current desktop controller. Restarting the app does not restore it.
If retry files disappear, the controller rejects the action and Results shows a failure message. Reported paths
alone do not establish availability. Terminal resume remains available when you have the required session context.

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
- use `--skip-tags` only when the target forge already contains all the tags you plan to migrate; this constraint is enforced at runtime
