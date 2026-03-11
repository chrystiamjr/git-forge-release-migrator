# Task

Render live run progress from the event-derived `RunState` model.

## Intent

Use the shared state contract from Sprint 2 to power the Run Progress and Migration Results screens without relying on
terminal scraping, direct engine access, or custom GUI-only progress logic.

## Detailed scope

- Subscribe GUI progress views to the runtime state stream exposed through `DesktopRunController`.
- Render current phase, lifecycle status, tag counters, release counters, latest failure, artifact availability, and
  retry-command visibility from `RunState`.
- Use the same state model to transition from active run progress to final results view.
- Ensure results rendering can expose summary and failure outputs without parsing terminal transcripts.
- Ensure progress updates remain deterministic and consistent with runtime events.

## Expected changes

- Run Progress becomes a live state-driven screen rather than a static placeholder.
- Migration Results can display final status, artifact shortcuts, and failure context from shared runtime state.
- The GUI reflects tag and release progress directly from `RunState`.
- The results flow aligns with actual artifact and retry semantics produced by the runtime.

## Non-goals and guardrails

- Do not parse console output to recover progress state.
- Do not query internal engine objects directly from GUI widgets.
- Do not create a second state model that can drift from runtime events.
- Do not hide failure details behind generic status messages when structured data exists.

## Test and validation

- Add widget tests for:
  - progress-state rendering
  - phase transition rendering
  - failure-state rendering
  - artifact availability rendering
- Add integration scenarios for:
  - successful run progress to completion
  - partial failure with retry available
  - validation stop after preflight
- Verify results and progress screens remain consistent with final artifact outputs.
- Keep existing runtime tests from earlier sprints passing unchanged.

## Exit criteria

- The GUI renders progress and results from `RunState`.
- Phase, counters, failures, artifacts, and retry visibility are all state-driven.
- No terminal scraping is required for live progress.
- The GUI reflects runtime outcomes consistently in controlled scenarios.
