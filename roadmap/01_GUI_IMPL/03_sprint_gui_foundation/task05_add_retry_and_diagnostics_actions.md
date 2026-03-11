# Task

Add retry and diagnostics actions that remain aligned with CLI semantics.

## Intent

Expose failure recovery and artifact-inspection actions in the GUI without inventing a second retry model or weakening
the existing `gfrm resume` contract.

## Detailed scope

- Add a `Retry Failed Tags` action to the GUI when retry semantics are valid.
- Route retry through resume-compatible runtime behavior exposed by `DesktopRunController`.
- Add actions for opening:
  - `summary.json`
  - `migration-log.jsonl`
  - `failed-tags.txt`
- Ensure retry availability is derived from runtime results and `RunState`, not from guesswork.
- Ensure diagnostics actions remain tied to actual artifacts produced by the run.

## Expected changes

- The GUI exposes a safe retry action only when the runtime indicates retry is valid.
- Retry uses the same conceptual contract as `gfrm resume`.
- Results and history surfaces can open run artifacts directly for diagnosis.
- Diagnostics UX remains grounded in real output files and shared runtime semantics.

## Non-goals and guardrails

- Do not create a custom GUI retry flow unrelated to resume semantics.
- Do not show retry actions when no retryable failure exists.
- Do not expose artifact actions for files that were not actually written.
- Do not hide operational failure details behind cosmetic success-first UI.

## Test and validation

- Add widget tests for retry-action visibility and disabled states.
- Add integration scenarios for:
  - retry available after failed tags
  - retry not available after non-retryable failure
  - opening summary, log, and failed-tags artifacts when they exist
  - artifact actions absent when outputs do not exist
- Verify retry-triggered runs still align with summary retry semantics.
- Keep earlier sprint runtime and GUI tests passing.

## Exit criteria

- Retry and diagnostics actions exist in the GUI.
- Retry remains aligned with the `gfrm resume` contract.
- Artifact actions operate on real outputs and not inferred placeholders.
- Failure recovery and diagnosis are available without semantic drift from the CLI.
