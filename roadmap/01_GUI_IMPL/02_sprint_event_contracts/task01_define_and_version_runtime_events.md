# Task

Define and version the canonical runtime event contract.

## Intent

Create a stable, explicit event schema that describes run lifecycle, phases, item progress, artifact completion, and
final outcome in a way that both CLI tooling and future GUI code can consume reliably.

## Detailed scope

- Introduce `RuntimeEventEnvelope` with the minimum shared metadata:
  - `schema_version`
  - `run_id`
  - `sequence`
  - `occurred_at`
  - `event_type`
  - `payload`
- Set the initial runtime event schema version to `1`, independent of `summary.json` schema version `2`.
- Define the minimum event catalog:
  - `run_started`
  - `preflight_completed`
  - `phase_started`
  - `item_started`
  - `item_completed`
  - `item_failed`
  - `phase_completed`
  - `artifact_written`
  - `run_completed`
  - `run_failed`
- Document which payload fields belong to each event and keep those payloads canonical rather than provider-specific.
- Require explicit schema-version handling for any future breaking event changes.

## Expected changes

- `RuntimeEventEnvelope` exists as a first-class runtime contract.
- Runtime event types are enumerated and no longer implied through log messages.
- Payloads become small, typed, and testable units rather than free-form text.
- `run_started` and `preflight_completed` provide enough metadata for early GUI readiness and status rendering.
- Completion events carry final status and retry context without requiring a consumer to parse `summary.json`.

## Non-goals and guardrails

- Do not reuse `summary.json` schema versioning for runtime events.
- Do not emit provider-native payloads directly.
- Do not define event semantics that depend on parsing arbitrary strings.
- Do not include secrets or full token-bearing config in payloads.
- Do not add speculative event types that are not justified by current CLI and planned GUI needs.

## Test and validation

- Add unit tests for envelope serialization and deserialization.
- Add contract tests proving the initial schema version is explicit and stable.
- Add snapshot or golden tests for representative payloads of each event type.
- Add regression checks ensuring final completion events stay consistent with summary retry semantics.
- Run `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- `RuntimeEventEnvelope` exists with an explicit versioned contract.
- The minimum event catalog is defined and documented in production code.
- Event payloads are canonical, serializable, and free of secrets.
- Future consumers can rely on event type plus schema version as the compatibility boundary.
