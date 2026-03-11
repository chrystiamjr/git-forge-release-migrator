# Task

Wire the new migration wizard to shared runtime contracts.

## Intent

Make the GUI capable of collecting migration intent, validating readiness, and starting runs through the shared
application layer rather than inventing a GUI-specific execution contract.

## Detailed scope

- Build the New Migration wizard on top of `RunRequest`.
- Define how the wizard captures:
  - source provider
  - target provider
  - source repository
  - target repository
  - settings profile
  - safe execution flags such as `skip_tags` and `dry_run`
- Surface structured preflight results before actual execution starts.
- Prepare or introduce the GUI-facing controller boundary:
  - `DesktopRunController`
  - `startRun(RunRequest)`
  - `resumeRun(...)`
  - `subscribeToRunState(run_id)`
  - `openArtifact(path)`
- Ensure GUI input handling respects the same token-precedence and settings behavior defined by the CLI contract.

## Expected changes

- The GUI can produce a valid `RunRequest` from wizard input.
- The GUI can trigger preflight and surface `ok`, `warning`, and `error` checks before starting execution.
- `DesktopRunController` becomes the GUI-to-runtime boundary instead of direct CLI subprocess calls.
- GUI start behavior aligns with the same runtime service used by the CLI.

## Non-goals and guardrails

- Do not invent GUI-only execution flags or relaxed validation rules.
- Do not let the wizard bypass structured preflight.
- Do not expose raw tokens in widget state, logs, or ad hoc storage.
- Do not shell out to `gfrm` for the default start-run path.

## Test and validation

- Add widget tests for wizard field validation and preflight display states.
- Add integration scenarios for:
  - valid request creation
  - blocking preflight failure
  - warning-only preflight that still allows execution
  - start-run flow invoking shared runtime contracts
- Add parity-focused checks ensuring wizard-derived requests map cleanly to the same logical `RunRequest` semantics used
  by the CLI.
- Keep existing Dart quality gates green with `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- The GUI can collect migration intent and build a valid `RunRequest`.
- Structured preflight is visible before execution.
- `DesktopRunController` or an equivalent typed GUI boundary exists.
- GUI start-run behavior is aligned with shared runtime contracts.
