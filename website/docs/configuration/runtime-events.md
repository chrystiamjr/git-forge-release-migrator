---
sidebar_position: 5
title: Runtime Events
---

GFRM now emits an ordered runtime event stream for each run.

## What it is for

Runtime events are meant for:

- runtime observability
- test assertions
- future GUI state updates

They complement the operator-facing artifacts, but do not replace `summary.json`, `failed-tags.txt`,
`migration-log.jsonl`, or `gfrm resume`.

## Ordering and sinks

- event ordering is authoritative per run
- supported sinks in this release: console, JSONL, in-memory, and reducer consumers
- sink-specific formatting stays outside the ordered publisher

The JSONL sink is a runtime-event consumer implementation. The public run artifact for operators remains
`migration-log.jsonl`.

## Event families

Examples of runtime events exposed in this release:

- `run_started`
- `preflight_completed`
- `tag_migrated`
- `release_migrated`
- `artifact_written`
- `run_completed`
- `run_failed`

These events can mirror progress state and written artifact paths, including `summary.json` and `failed-tags.txt`.

## Public contract

Use runtime events when you need ordered runtime visibility inside the app, tests, or future GUI layers.
Use `summary.json`, `failed-tags.txt`, `migration-log.jsonl`, and `gfrm resume` when you need the public operational
contract for triage and recovery.
