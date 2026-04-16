---
applyTo: "dart_cli/lib/**/*.dart,dart_cli/test/**/*.dart"
---

# Dart Review Rules

- Treat `AGENTS.md` as the source of truth for CLI contract, invariants, and architecture.
- Preserve public commands: `migrate`, `resume`, `demo`, `setup`, `settings`.
- Prefer minimal additive changes over broad rewrites.
- Ignore generated files, lock files, harmless formatting, and import ordering.

## Block Merge If Violated

- Token precedence changes:
  - `migrate`: settings `token_env`, then `token_plain`, then env aliases.
  - `resume`: session token context, then settings `token_env`, then `token_plain`, then env aliases.
- Hidden compatibility flags `--source-token` and `--target-token` are removed or broken.
- Tags no longer migrate before releases.
- `--skip-tags` becomes a generic shortcut instead of a constrained escape hatch.
- Release selection expands beyond semver `vX.Y.Z`.
- `summary.json` changes from `schema_version: 2`.
- Failed run retry guidance stops using `gfrm resume`.
- Never log raw tokens or expose secret values in errors, output, fixtures, or docs.
- Success/failure exit code behavior changes.

## Tests Expected

- `config.dart`, `core/settings.dart`, setup handlers -> config/settings tests.
- `selection.dart`, `engine.dart`, `tag_phase.dart`, `release_phase.dart` -> selection/phase tests.
- `summary.dart`, `cli.dart`, `application/run_service.dart` -> summary/run tests.
- `run_paths.dart`, `runtime_options.dart` -> artifact/session path tests.
- `arg_parsers.dart` -> command surface/parser tests.
- New public Dart source over 30 lines needs focused tests.

## Error Handling

Flag when you see:

- `throw Exception(` or `throw StateError(` in production code where project exceptions fit.
- `catch (e)` without rethrowing or logging.
- `catch (e) { return null; }` masking real failures.
- Broad `on Object catch` around large methods.
- Missing `await` on Future-returning calls.
- Secret/token interpolation in logs or errors.

## HTTP, Providers, Resume

Flag when you see:

- HTTP calls without configured `HttpConfig` timeouts.
- Retry on POST/PUT/DELETE without idempotency guarantees.
- Hard-coded API base URLs that should come from provider configuration.
- Engine or phase code calling concrete provider APIs directly.
- Engine importing concrete providers instead of using registry/adapter abstractions.
- Provider adapter returning raw JSON where typed models exist.
- New provider method without provider tests.
- Bitbucket synthetic release model broken: tag + notes + downloads + `.gfrm-release-<tag>.json`.
- Checkpoint transitions skipping terminal states.
- Resume logic re-processing completed items.
- Checkpoint writes without atomic semantics.
- `RunStatePhase` or `RunStateLifecycle` changes without switch/case updates.

## Architecture

The Dart CLI has strict layer boundaries:

- `cli.dart`: entry point only.
- `application/`: orchestration, run service, preflight.
- `migrations/`: selection, phases, summary, execution. No direct API calls.
- `providers/`: forge API translation.
- `core/`: shared infrastructure.

Flag when you see:

- Business logic in `cli.dart`.
- `application/` importing CLI entry points or arg parsers.
- Provider adapters owning migration business rules.
- Multiple public classes in one file.
- New file over 500 lines or method over 120 lines.

## Code Quality

Flag when you see:

- `var` instead of explicit type or `final` for values never reassigned.
- `dynamic` type where a concrete type is known.
- `print(` in production code — use logging infrastructure.
- Magic strings or numbers without named constants.
- `if (source is ...)` runtime type dispatch in engine flow.
- String concatenation for paths instead of `path` package.
