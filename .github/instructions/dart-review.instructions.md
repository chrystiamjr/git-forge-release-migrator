---
applyTo: "dart_cli/lib/**/*.dart,dart_cli/test/**/*.dart"
---

# Dart Review Rules

- Treat `AGENTS.md` as the source of truth for CLI contract, invariants, and architecture.
- Preserve the current CLI surface: `migrate`, `resume`, `demo`, `setup`, `settings`.
- Prefer additive, minimal changes over broad rewrites in migration flow or provider logic.

## Contract Invariants (block merge if violated)

- Token precedence is deterministic:
  - `migrate`: settings `token_env`, then `token_plain`, then env aliases
  - `resume`: session token context, then settings `token_env`, then `token_plain`, then env aliases
- Hidden compatibility flags `--source-token` and `--target-token` still exist; do not break them casually.
- Tags-first is mandatory. Releases depend on destination tags unless `--skip-tags` is explicitly used.
- `--skip-tags` is not a shortcut for general migrations. Keep its safety expectations intact.
- Release selection remains semver-only for `vX.Y.Z`. Do not broaden selection unless the repository intentionally changes that policy.
- `summary.json` stays on `schema_version: 2` and failed runs must keep a retry command based on `gfrm resume`.
- Never log raw tokens or expose secret values in errors, output, fixtures, or docs.
- Exit code 0 on success, non-zero on failure. No silent swallowing.

## Test Coverage Expectations

When risky files change, expect focused tests:

- `config.dart`, `core/settings.dart`, `settings_setup_command_handler.dart` -> config/settings tests
- `selection.dart`, `engine.dart`, `tag_phase.dart`, `release_phase.dart` -> selection/phase tests
- `summary.dart`, `cli.dart`, `application/run_service.dart` -> summary/runner tests
- `run_paths.dart`, `runtime_options.dart` -> artifact/session path tests
- `arg_parsers.dart` -> command surface and parser tests
- New public Dart source (>30 lines) without any test file -> block merge

## Exception Handling Heuristics

Flag when you see:

- `throw Exception(` or `throw StateError(` — should use project-specific exceptions: `HttpRequestError`, `AuthenticationError`, `MigrationPhaseError`.
- `catch (e)` without rethrowing or logging — silent error swallowing hides failures.
- `catch (e) { return null; }` — masks real errors; prefer letting exceptions propagate or logging with context.
- `on Object catch` or `on dynamic catch` — too broad; catch specific types.
- Missing `rethrow` after logging in catch blocks that should propagate errors.
- `try/catch` around entire methods — narrow the scope to the specific risky operation.

## HTTP and Retry Safety Heuristics

Flag when you see:

- HTTP calls without timeout from `HttpConfig` — must use configured `connect_timeout_ms` and `receive_timeout_ms`.
- Missing retry logic on GET requests to forge APIs — use the exponential backoff in `requestJson()`.
- Retry on POST/PUT/DELETE without idempotency guarantees — risk of duplicate operations.
- `catch` blocks swallowing HTTP errors without logging status code, URL, and method.
- Hard-coded URLs or API base paths — should come from provider configuration.
- `requestStatus()` used where `requestJson()` is needed — `requestStatus()` only returns status codes.
- Missing `Content-Type` header on POST/PUT requests.
- Authentication tokens interpolated into log messages or error strings.

## Provider Adapter Heuristics

Flag when you see:

- Engine code (`migrations/engine.dart`) calling provider APIs directly — must go through adapters.
- Provider adapter returning raw JSON — should return typed models.
- New provider method without corresponding test in the provider's test file.
- Inconsistent error handling across providers — all three (GitHub, GitLab, Bitbucket) should handle 401/403 the same way via `AuthenticationError`.
- Bitbucket adapter not handling synthetic release model (tag + notes + downloads + `.gfrm-release-<tag>.json`).
- Provider adapter with hard-coded pagination limits — should use configurable page sizes.

## State Machine and Checkpoint Heuristics

Flag when you see:

- Checkpoint state transitions that skip terminal states — completed items must stay completed.
- Resume logic that re-processes already-completed items — breaks idempotency.
- Missing terminal state check before writing checkpoint — risk of overwriting completed state.
- Checkpoint file writes without atomic semantics (write-then-rename).
- `RunStatePhase` or `RunStateLifecycle` enum changes without updating all switch/case handlers.

## Clean Architecture Boundaries

The Dart CLI has strict layer boundaries:

- `cli.dart` is an entry point — delegates to `application/` layer, no business logic.
- `application/` orchestrates runs — calls `migrations/` engine and `providers/` adapters.
- `migrations/` is the execution engine — selection, phases, summary. No direct API calls.
- `providers/` adapters translate forge API calls — no business logic, only API mediation.
- `core/` is shared infrastructure — HTTP, settings, logging, types. No domain logic.

Flag when you see:

- Business logic in `cli.dart` — delegate to `application/` or `migrations/`.
- Direct HTTP calls in `migrations/engine.dart` or phase runners — must go through provider adapters.
- Engine importing concrete providers (`github.dart`, `gitlab.dart`) — depend on abstractions via `ProviderRegistry`.
- Provider adapters containing business rules (filtering, selection, retry decisions) — keep them as pure API translators.
- `application/` layer importing `cli.dart` or `config/arg_parsers.dart` — wrong direction.
- Multiple public classes in one file — one public class per file (SRP).
- New file over 500 lines — decompose into focused units.

## Code Style Heuristics

Flag when you see:

- `var` instead of `final` for variables never reassigned.
- `dynamic` type where a concrete type is known.
- `print(` in production code — use logging infrastructure.
- Methods over 120 lines.
- Files over 500 lines.
- Magic strings or numbers without named constants.
- `if (source is ...)` runtime type dispatch in engine flow.
- Missing `await` on Future-returning calls.
- String concatenation for paths — use `path` package functions.
- Unused imports left after refactoring.
