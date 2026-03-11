# Task

Add serial runtime-event publisher infrastructure with pluggable sinks.

## Intent

Guarantee deterministic event delivery across multiple consumers so the same run can feed console output, machine
readable persistence, state aggregation, and tests without ordering drift.

## Detailed scope

- Introduce a publisher responsible for assigning `sequence` values centrally per run.
- Ensure events are emitted one at a time in deterministic order.
- Define pluggable sink abstractions for at least:
  - console sink
  - JSONL sink
  - in-memory sink
  - reducer or state-consumer sink
- Ensure all registered sinks observe the same ordered event stream for the same run.
- Define sink-failure handling so mandatory sinks can fail the run explicitly when contract integrity would be lost.

## Expected changes

- Runtime event publishing becomes a shared infrastructure concern instead of an ad hoc side effect.
- Multiple consumers can subscribe to one run without each reconstructing state independently.
- `sequence` becomes the ordering authority rather than wall-clock timing.
- Console diagnostics and machine-readable persistence can evolve from the same canonical event stream.
- Test code gains a deterministic in-memory observation path for validating run behavior.

## Non-goals and guardrails

- Do not let sinks control orchestration flow.
- Do not use timestamps as the primary ordering mechanism.
- Do not silently swallow failures from mandatory persistence sinks.
- Do not publish secret-bearing objects directly to sinks.
- Do not couple publisher logic to GUI widgets or CLI-specific formatting.

## Test and validation

- Add unit tests verifying monotonically increasing `sequence` values per run.
- Add tests proving multiple sinks observe identical event order for the same run.
- Add failure-path tests showing mandatory sink failures are surfaced explicitly.
- Add in-memory sink tests that capture full ordered streams for representative runs.
- Run `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- A shared publisher exists and owns ordered event delivery.
- Console, JSONL, in-memory, and state-oriented sinks can observe the same stream.
- Ordering is deterministic and based on `sequence`.
- Mandatory sink failures are visible and not silently ignored.
