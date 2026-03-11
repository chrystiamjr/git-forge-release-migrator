# Task

Tighten boundaries between CLI, application, core, and provider layers.

## Intent

Use the service-layer refactor to make ownership boundaries explicit, reduce orchestration density, and keep
provider-specific behavior out of the shared execution flow.

## Detailed scope

- Clarify the responsibilities of each layer:
  - CLI owns argument parsing, terminal output, and process exit
  - application owns orchestration coordination and typed result mapping
  - core owns shared primitives such as files, checkpointing, settings, logging, and exceptions
  - providers own provider-specific normalization and remote behavior
- Split dense orchestration helpers when needed to stay inside repository complexity ceilings.
- Remove any new temptation to dispatch behavior by runtime type checks inside the engine flow.
- Ensure future GUI integration points are aimed at the application layer, not at provider or CLI internals.

## Expected changes

- Service-layer boundaries are documented in code and reflected in class and helper responsibilities.
- Orchestration methods are smaller and more single-purpose.
- Provider-specific rules remain inside adapters or provider-facing helpers.
- The engine continues to execute canonical migration behavior without GUI- or CLI-specific branches being introduced.
- Future event publication work in Sprint 2 has a stable place to attach without expanding CLI responsibility again.

## Non-goals and guardrails

- Do not introduce runtime-type dispatch such as `if (source is X)` or `if (target is Y)` in orchestration flow.
- Do not create a god service that absorbs unrelated concerns.
- Do not move core-layer responsibilities upward just for convenience.
- Do not refactor unrelated modules merely for naming consistency.
- Do not exceed the repository method and orchestration-file complexity ceilings.

## Test and validation

- Review affected flows to confirm all callsites now pass through the intended layer boundaries.
- Add or update tests where refactoring changes helper seams or responsibilities.
- Run feature and integration scenarios to prove unaffected provider pairs still behave the same.
- Verify that no contract drift appears in:
  - CLI command compatibility
  - token precedence
  - artifact outputs
  - retry semantics
- Run `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- Layer ownership is explicit and coherent.
- No new runtime-type dispatch is added to the engine flow.
- Orchestration complexity is reduced rather than redistributed into another large class.
- The runtime is prepared for Sprint 2 event-contract work without boundary confusion.
