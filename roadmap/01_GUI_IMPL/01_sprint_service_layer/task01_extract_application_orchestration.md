# Task

Extract application orchestration into a reusable service-layer entrypoint for `migrate` and `resume`.

## Intent

Move orchestration responsibility out of CLI command handlers and into a typed service that future GUI code can call
directly, while preserving the exact runtime behavior already exposed through the CLI.

## Detailed scope

- Introduce an application-level execution service that becomes the single orchestration entrypoint for `migrate` and
  `resume`.
- Define and document the core request/result contracts used by that service:
  - `RunRequest`
  - `RunResult`
  - `RunFailure`
- Make the service responsible for the full lifecycle:
  - request intake from already parsed inputs
  - validation and preflight coordination
  - migration context creation
  - execution through existing engine flow
  - summary and artifact finalization
  - typed result mapping
- Ensure `RunFailure` can distinguish validation failures, execution failures, and artifact-finalization failures.
- Ensure the service can represent success, partial failure, validation failure, and runtime failure without requiring
  the CLI to infer those states indirectly.

## Expected changes

- A new application-layer service exists in Dart production code and is callable without terminal I/O.
- `RunRequest` is introduced as a typed input contract and accepts already resolved command intent, not raw CLI strings.
- `RunResult` is introduced as a typed output contract carrying run status, exit code, artifact paths, retry command,
  preflight data, and failure collection.
- `RunFailure` is introduced as a typed failure contract carrying scope, code, message, retryability, and optional tag or
  phase context.
- The orchestration sequence becomes explicit and shared:
  1. receive typed request
  2. evaluate preflight
  3. build runtime context
  4. execute migration
  5. finalize artifacts
  6. return typed result
- Existing engine and provider adapters remain the execution core; this task only relocates orchestration ownership.

## Non-goals and guardrails

- Do not turn `RunRequest` into a second CLI parser.
- Do not change public CLI flags, names, or exit semantics.
- Do not move provider-specific behavior into the application layer.
- Do not change artifact names, artifact paths, or `summary.json` schema version.
- Do not weaken the current `gfrm resume` retry contract.

## Test and validation

- Add unit tests for `RunResult` status classification and typed failure mapping.
- Add unit tests confirming `RunRequest` rejects missing required fields only at the service contract level, not through
  ad hoc terminal parsing.
- Add feature coverage proving the CLI still reports the same success and failure exit codes after the orchestration
  extraction.
- Add integration scenarios for:
  - successful migrate flow
  - partial failure with generated retry command
  - fatal validation stop before migration execution
  - resume flow still using the same artifact contract
- Run `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- A single typed service can execute both `migrate` and `resume`.
- `RunRequest`, `RunResult`, and `RunFailure` exist as explicit contracts in production code.
- CLI-visible behavior remains unchanged.
- Runtime execution no longer depends on CLI handlers owning orchestration details.
