# Task

Preserve existing artifact and summary contracts while adding runtime observability.

## Intent

Ensure the new event system enriches observability without redefining the established CLI output contract that users and
tests already depend on.

## Detailed scope

- Keep writing the required artifact set:
  - `migration-log.jsonl`
  - `summary.json`
  - `failed-tags.txt`
- Keep `summary.json` on schema version `2`.
- Keep `retry_command` conceptually bound to `gfrm resume`.
- Ensure `artifact_written`, `run_completed`, and `run_failed` events remain consistent with actual artifact and summary
  outputs.
- Ensure event introduction does not change checkpoint semantics, skip semantics, or idempotent resume behavior.

## Expected changes

- Runtime events augment visibility but do not replace existing artifact generation.
- Existing downstream consumers of `summary.json` and failure artifacts continue to work unchanged.
- Final event payloads align with actual outputs written on disk.
- The event system becomes an additive contract layered on top of existing run artifacts.

## Non-goals and guardrails

- Do not redefine the artifact contract around event streams.
- Do not change `summary.json` schema version or field meaning.
- Do not let event publication drift from actual final outputs.
- Do not weaken checkpoint terminal-state semantics in order to emit more events.
- Do not change failed-tag behavior or retry semantics.

## Test and validation

- Add integration tests comparing final event payloads against generated artifacts.
- Add regression checks proving `summary.json` still reports schema version `2`.
- Add tests ensuring failure runs still produce `failed-tags.txt` and a retry command when applicable.
- Add tests confirming event introduction does not alter idempotent resume outcomes.
- Run `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- Artifact generation remains unchanged from the user perspective.
- Runtime events and final outputs remain consistent with one another.
- Summary and retry semantics are preserved exactly where current contracts require them.
- Sprint 2 observability work does not cause CLI contract drift.
