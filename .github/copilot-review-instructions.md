# Copilot PR Review Instructions

Use [AGENTS.md](../AGENTS.md) as the primary repository context before reviewing.

## Review Stance

- You are reviewing a Dart CLI + Flutter desktop app that migrates releases across Git forges.
- Correctness and safety over style. Do not comment on formatting, naming preferences, or import order unless they break linting.
- Comment only on concrete problems, regressions, security issues, or contract drift.
- No praise, no summaries, no generic "looks good" comments.
- Every comment must be inline, specific, and actionable.

## Severity Taxonomy

Use these severity prefixes in every comment:

- `[critical]` — Security issue, data loss, broken invariant, or regression. Blocks merge.
- `[important]` — Correctness bug, missing test coverage for risky change, contract drift. Blocks merge.
- `[suggestion]` — Improvement that does not block merge. Readability, performance, simplification.
- `[question]` — Ambiguous intent. Ask for clarification before judging.

## Review Dimensions

Evaluate changes across these dimensions in order of priority:

1. **Correctness and safety** — Does it do what it claims? Does it break existing behavior?
2. **Contract compliance** — Does it preserve the product contract in AGENTS.md?
3. **Security** — Token handling, secret exposure, input validation at boundaries.
4. **Test coverage** — Are risky changes covered? Are new public APIs tested?
5. **Documentation sync** — If behavior changed, are docs updated in both locales?
6. **Readability** — Can a new contributor understand this without extra context?

## Critical Invariants (block merge if violated)

- Tags migrate before releases. `--skip-tags` is a constrained escape hatch, not a shortcut.
- Release selection stays semver-only for `vX.Y.Z`. Do not broaden.
- `summary.json` stays on `schema_version: 2`.
- Retry guidance uses `gfrm resume`, never `gfrm migrate`.
- Token precedence is deterministic: settings `token_env` > `token_plain` > env aliases.
- Raw tokens never appear in logs, errors, output, fixtures, or docs.
- Exit code 0 on success, non-zero on failure. No silent swallowing.

## False-Positive Exclusions (do NOT flag these)

- Generated files (`*.g.dart`, `*.freezed.dart`) — skip entirely.
- Test fixtures and golden files — trust the test author unless content is clearly wrong.
- Lock file changes (`pubspec.lock`, `package-lock.json`) — skip unless security-relevant.
- Import reordering by formatters — skip.
- Changelog and version bump commits from semantic-release — skip.

## DRY, SOLID, and Clean Architecture Heuristics

### Single Responsibility (SRP)

Flag when you see:

- Multiple class declarations in a single file (except private helpers) — one public class per file.
- Widget that fetches data, transforms it, AND renders it — split into controller + widget.
- Service class that handles both business logic and data persistence — split into service + repository.
- File over 500 lines — likely doing too much, needs decomposition.
- Method over 120 lines — extract sub-operations into focused private methods.
- Controller that manages UI state AND calls APIs AND transforms data — separate concerns.

### Open/Closed Principle (OCP)

Flag when you see:

- `if (source is GitHubProvider)` or `switch` on provider type in engine code — use polymorphism via adapter interfaces.
- New functionality added by modifying existing methods instead of extending via new classes or methods.
- Hard-coded feature flags or conditional branches where a strategy pattern would be cleaner.

### Liskov Substitution (LSP)

Flag when you see:

- Provider adapter that throws `UnimplementedError` for interface methods — all adapters must implement the full interface.
- Subclass that narrows preconditions or changes behavior contracts of the parent.

### Interface Segregation (ISP)

Flag when you see:

- Provider adapter interface with methods not needed by all forge types — split into focused interfaces.
- Widget accepting a large controller when it only uses one or two fields — pass specific data, not the whole controller.

### Dependency Inversion (DIP)

Flag when you see:

- Engine code importing concrete provider implementations — depend on abstractions.
- GUI importing CLI-specific code (`cli.dart`, `arg_parsers.dart`) — use the application layer.
- Direct instantiation of services inside widgets — use Riverpod providers for DI.
- `new ConcreteClass()` in business logic where an interface injection is appropriate.

### DRY (Don't Repeat Yourself)

Flag when you see:

- Same API call logic duplicated across provider adapters — extract to shared base or helper.
- Identical error handling blocks repeated more than twice — extract to a shared handler.
- Copy-pasted widget subtrees — extract to a reusable widget.
- Same string literal used in 3+ places without a named constant.
- Duplicate mapping/transformation logic — consolidate into a single mapper function.

### Clean Architecture Layers

This project has clear layer boundaries:

**Dart CLI layers:**
- `cli.dart` — entry point, no business logic
- `application/` — orchestration (run_service, preflight_service)
- `migrations/` — execution engine (selection, phases, summary)
- `providers/` — forge API adapters
- `core/` — shared infrastructure (HTTP, settings, logging)

**Flutter GUI layers:**
- `app/` — shell, navigation, layout
- `features/*/presentation/` — pages and widgets (render-only)
- `runtime/run/` — controllers and providers (state management)
- `application/` — shared data models and contracts
- `theme/` — design tokens

Flag when you see:

- Business logic in entry points (`cli.dart`, widget `build()` methods).
- Data access in service/orchestration layer — should go through repositories or adapters.
- Cross-layer imports that skip a level (widget importing core/http directly).
- Models that import Flutter or CLI dependencies — models should be framework-agnostic.
- Provider adapters containing business logic — they should only translate API calls.

## Domain Heuristics: Dart CLI

Flag when you see:

- `throw Exception(` or `throw StateError(` in production code — should use `HttpRequestError`, `AuthenticationError`, or `MigrationPhaseError`.
- `var` instead of `final` for variables that are never reassigned.
- Direct Eloquent-style calls in engine code — provider adapters must mediate all forge API calls.
- `print(` in production code — should use the logging infrastructure.
- String interpolation containing token or secret values.
- `catch (e)` without rethrowing or logging — silent error swallowing.
- Missing `await` on Future-returning calls.
- `dynamic` type where a concrete type is known.
- Methods over 120 lines or files over 500 lines.
- Magic strings or numbers without named constants.
- `if (source is ...)` runtime type dispatch in engine flow.

## Domain Heuristics: Flutter GUI

Flag when you see:

- `setState()` usage — this project uses Riverpod, not StatefulWidget state.
- `Provider.of(context)` or `context.read/watch` without Riverpod — wrong state management.
- Business logic inside widget `build()` methods — should live in controllers or providers.
- Hard-coded colors or text styles — should use `GfrmColors`, `GfrmTypography`, or theme tokens.
- Hard-coded strings in UI — should use localization.
- Missing `const` constructor on stateless widgets with no mutable fields.
- Widget files mixing presentation and data fetching — separate into controller + widget.
- `keepAlive: true` on providers that should be scoped to a page lifecycle.
- Missing `.when()` or `.maybeWhen()` handling for `AsyncValue` — must handle loading, error, and data states.
- Platform-specific code without platform guards (macOS title bar padding, etc.).

## Domain Heuristics: HTTP and Retry

Flag when you see:

- HTTP calls without timeout configuration.
- Missing retry logic on non-idempotent operations.
- Retry on POST/PUT/DELETE without idempotency guarantees.
- `catch` blocks that swallow HTTP errors without logging status code and URL.
- Hard-coded URLs or API paths that should come from provider configuration.
- Missing `Content-Type` headers on POST/PUT requests.

## Domain Heuristics: Migration Safety

Flag when you see:

- Checkpoint state transitions that skip terminal states (completed items must stay completed).
- Resume logic that re-processes already-completed items.
- Asset download without checksum or size verification when available.
- Tag creation after release creation (violates tags-first).
- Release selection matching non-semver tags.
- Summary generation that omits required fields (`schema_version`, `retry_command`, `failed-tags.txt`).

## Domain Heuristics: Security

Flag when you see:

- Tokens or credentials in string literals, test fixtures, or comments.
- `Authorization` header values logged or included in error messages.
- Environment variable names that suggest secrets used in non-secret contexts.
- File paths that could write outside the expected `migration-results/` directory.
- User input used in file paths without sanitization (path traversal).

## Domain Heuristics: Workflows and CI

Flag when you see:

- `GITHUB_TOKEN` where `GH_TOKEN` should be used for bot flows.
- Missing `continue-on-error` awareness — silent failures in review pipeline.
- Workflow changes that weaken branch protection or required checks.
- Secrets referenced but not documented in workflow comments.
- Shell commands with unquoted variables (`$VAR` instead of `"$VAR"`).
- Missing `set -e` or equivalent error propagation in shell steps.

## Documentation Sync

When code changes affect user-visible behavior, flag if missing:

- English docs under `website/docs/**`
- PT-BR docs under `website/i18n/pt-BR/docusaurus-plugin-content-docs/current/**`
- `README.md` for high-level contract changes
- `dart_cli/README.md` for developer workflow changes

## Comment Format

```
[severity] Concrete description of the problem.

Why: explanation of the risk or regression.

Suggestion: specific fix or alternative.
```

Example:
```
[critical] This catches `Exception` without rethrowing, silently swallowing authentication failures.

Why: AuthenticationError extends HttpRequestError — catching broadly here means 401/403 errors are hidden from the caller, breaking retry logic.

Suggestion: Catch `HttpRequestError` specifically or rethrow after logging.
```
