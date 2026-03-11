# Task

Define and enforce CLI and GUI parity validation for release readiness.

## Intent

Prevent the GUI from drifting semantically away from the CLI by treating behavior mismatches as explicit release
problems rather than post-release surprises.

## Detailed scope

- Create a parity checklist covering:
  - migrate semantics
  - resume semantics
  - token precedence
  - artifact names and locations
  - `summary.json` schema version `2`
  - retry behavior aligned with `gfrm resume`
- Define representative scenarios that must be exercised through both interfaces.
- Treat any user-visible semantic mismatch as a release blocker.
- Ensure parity validation includes failure cases, not only success cases.
- Ensure parity checks remain grounded in the established CLI contract from `AGENTS.md`.

## Expected changes

- Release readiness includes an explicit CLI/GUI parity matrix.
- GUI behavior is evaluated against CLI semantics rather than against its own independent expectations.
- Migrate, resume, retry, and artifact behavior can be compared systematically across both interfaces.
- Release decisions gain a concrete basis for accepting or rejecting GUI-enabled candidates.

## Non-goals and guardrails

- Do not reduce parity to superficial UI similarity.
- Do not skip failure and retry scenarios.
- Do not redefine CLI semantics to match GUI shortcuts.
- Do not call parity complete while artifact or summary behavior still diverges.

## Test and validation

- Add release-candidate scenarios covering:
  - CLI migrate vs GUI migrate
  - CLI resume vs GUI retry or resume path
  - token precedence across settings, session context, and environment aliases
  - artifact generation and summary compatibility
  - retry visibility and retry execution after failed tags
- Document the expected result for each parity scenario.
- Keep runtime quality gates green alongside parity checks.

## Exit criteria

- A documented parity matrix exists and is actionable.
- Representative CLI and GUI scenarios can be compared directly.
- Semantic mismatches are treated as blockers.
- GUI release readiness is measured against CLI contract fidelity.
