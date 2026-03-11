# Task

Introduce a structured preflight service that can be consumed by both CLI and future GUI flows.

## Intent

Replace terminal-only validation reporting with a typed preflight model so both interfaces can evaluate readiness,
display actionable warnings, and block fatal runs consistently.

## Detailed scope

- Introduce `PreflightCheck` as a typed contract with:
  - `status: ok | warning | error`
  - `code`
  - `message`
  - optional `hint`
  - optional `field`
- Centralize reusable startup validation in a single preflight service.
- Ensure preflight covers at least:
  - supported provider pair
  - repository URL validity or shape
  - token-resolution presence
  - settings profile availability and readiness
- Ensure preflight returns structured output before any migration work begins.
- Ensure fatal `error` checks block execution deterministically.
- Ensure `warning` checks remain informative and do not alter exit status by themselves.

## Expected changes

- Preflight logic is exposed as typed data instead of only rendered terminal text.
- `RunResult` carries preflight information so callers can inspect readiness outcomes directly.
- The CLI can continue to render checks in human-readable form, but the underlying validation source is now structured.
- Future GUI code can present readiness state without scraping log lines or terminal output.
- Validation messaging gains stable codes and fields that can be reused in tests and UI rendering.

## Non-goals and guardrails

- Do not log or persist raw token values in preflight output.
- Do not downgrade deterministic blocking failures into warnings.
- Do not move provider-specific normalization rules out of provider-aware layers if they already belong there.
- Do not make preflight dependent on terminal rendering or stdout formatting.
- Do not add speculative GUI-only fields that are not needed for shared validation.

## Test and validation

- Add unit tests covering `ok`, `warning`, and `error` classification.
- Add unit tests for stable preflight codes and field mapping for common failures.
- Add feature scenarios proving the CLI can still show actionable validation feedback without behavior drift.
- Add integration scenarios for:
  - unsupported provider pair
  - malformed repository URL
  - missing token resolution
  - invalid or missing settings profile
  - warning-only preflight that still allows execution
- Run `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- `PreflightCheck` exists as a typed shared contract.
- Fatal preflight failures block execution before migration starts.
- Warnings remain non-blocking.
- Both CLI and future GUI can consume the same structured readiness model.
