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

## `run_started` Event Structure

The `run_started` event is emitted as part of the ordered runtime event stream. In the JSONL sink, it is wrapped in a `RuntimeEventEnvelope`:

```json
{
  "event_type": "run_started",
  "timestamp": "2026-04-20T20:30:00.000Z",
  "payload": {
    "source_provider": "github",
    "target_provider": "gitlab",
    "mode": "migrate",
    "dry_run": false,
    "skip_tags": false,
    "skip_releases": false,
    "skip_release_assets": false,
    "settings_profile": "my-profile"
  }
}
```

**Envelope structure:**
- `event_type`: Always `"run_started"`
- `timestamp`: ISO 8601 timestamp when the event was emitted
- `payload`: Event-specific data (see fields below)

**Payload fields:**
- `source_provider`: Source forge (`github`, `gitlab`, `bitbucket`)
- `target_provider`: Target forge (`github`, `gitlab`, `bitbucket`)
- `mode`: Command name (`migrate` or `resume`)
- `dry_run`: Whether the run is in dry-run mode
- `skip_tags`: Whether tag migration is skipped (from `--skip-tags`)
- `skip_releases`: Whether release migration is skipped (from `--skip-releases`)
- `skip_release_assets`: Whether release asset migration is skipped (from `--skip-release-assets`)
- `settings_profile`: Optional settings profile name (if provided)

## Public contract

Use runtime events when you need ordered runtime visibility inside the app, tests, or future GUI layers.
Use `summary.json`, `failed-tags.txt`, `migration-log.jsonl`, and `gfrm resume` when you need the public operational
contract for triage and recovery.
