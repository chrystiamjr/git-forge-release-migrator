# Task

Build a deterministic `RunState` reducer from the canonical runtime event stream.

## Intent

Provide a UI-friendly runtime snapshot model so future progress screens and diagnostics consumers can render current
status directly from events instead of scraping logs or interrogating engine internals.

## Detailed scope

- Introduce `RunState` as a derived contract carrying at least:
  - `run_id`
  - lifecycle status
  - active phase
  - preflight summary
  - tag counters
  - release counters
  - latest failure
  - artifact paths
  - retry command
- Implement a reducer or aggregator that derives `RunState` solely from ordered event application.
- Ensure repeated application of the same event sequence always produces the same snapshot.
- Ensure the model is shaped for direct consumption by future GUI progress views.
- Ensure `RunState` reflects final artifact availability and retry information once the run completes.

## Expected changes

- `RunState` exists as a typed contract rather than an informal UI concept.
- State derivation becomes deterministic and replayable from captured event streams.
- Progress counters for tags and releases become reusable across CLI diagnostics, tests, and GUI rendering.
- Failure state becomes explicit and queryable without scraping text logs.
- Artifact shortcuts and retry availability can be rendered from the same state model.

## Non-goals and guardrails

- Do not let `RunState` depend on direct engine introspection or mutable internal globals.
- Do not store redundant provider-native payloads in the state snapshot.
- Do not design the state shape around one specific screen at the expense of general run observability.
- Do not require log parsing to recover progress information already available in events.
- Do not make the reducer nondeterministic.

## Test and validation

- Add reducer tests for:
  - fully successful run
  - partial failure run with retry command
  - fatal validation stop after preflight
  - artifact completion reflected in final state
- Add replay tests proving identical event lists produce identical snapshots.
- Add tests ensuring tag and release counters evolve correctly across phase transitions.
- Run `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- `RunState` exists as a typed derived contract.
- State snapshots can be reconstructed deterministically from ordered events.
- Progress, failures, artifacts, and retry data are available without log scraping.
- The reducer is suitable as the data source for Sprint 3 progress screens.
