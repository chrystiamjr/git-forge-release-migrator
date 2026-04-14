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
- sinks now declare an explicit failure mode: `optional` or `mandatory`

The JSONL sink is a runtime-event consumer implementation. The public run artifact for operators remains
`migration-log.jsonl`.

## Failure policy

- `optional` sinks are best-effort: failures are logged and the run continues
- `mandatory` sinks fail the run immediately when they cannot consume an event

Use `mandatory` only when the consumer is part of the required runtime contract for your embedding layer.

## Derived `RunState`

The reducer sink can derive a typed `RunState` snapshot from the ordered event stream.

The current snapshot model includes:

- lifecycle status
- active phase
- preflight summary
- tag and release counters
- per-tag and per-release progress entries
- artifact paths
- retry command and final completion status
- latest failure context

This state is meant for GUI, tests, and in-process diagnostics. It stays provider-agnostic and replay-safe because it
is derived only from the canonical runtime events above.

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
