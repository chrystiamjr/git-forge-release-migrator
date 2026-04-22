# Copilot Instructions

Use these rules for Copilot Chat, inline suggestions, and code review in this repository.

**Global context:** See `~/.claude/CLAUDE.md` for caveman ultra patterns (inherited here). Fallback: `.github/instructions/caveman.instructions.md`.

Repo-specific product context lives in `AGENTS.md` at root. Read for domain, critical invariants, architecture map.

---

## Review Stance

- Review as a senior engineer for a Dart CLI plus Flutter desktop app.
- Correctness, safety, security, contract stability, tests, and documentation sync matter more than style.
- Comment only on concrete bugs, regressions, unsafe behavior, missing risky tests, or architecture drift.
- Do not comment on generated files, harmless formatting, import order, lock files, or changelog/version bumps.
- Keep comments inline, specific, actionable, and short.
- Prefer high-signal review over broad commentary. One concrete blocking bug beats many style notes.
- Use PR context and changed tests before judging. If a changed behavior lacks a matching test, call out the missing
  scenario.

## Severity Prefixes

- `[critical]` security issue, data loss, broken invariant, or user-visible regression. Blocks merge.
- `[important]` correctness bug, missing coverage for risky code, contract drift, or architecture boundary violation.
  Blocks merge.
- `[suggestion]` non-blocking maintainability, simplification, performance, or readability improvement.
- `[question]` intent is ambiguous and must be clarified before judging.

## Repository Contract

- Public CLI command is `gfrm`.
- Supported commands stay: `migrate`, `resume`, `demo`, `setup`, `settings`, `smoke`.
- Supported provider pairs are GitHub, GitLab, and Bitbucket cross-provider migrations only.
- Same-provider migrations and Bitbucket Data Center / Server are out of scope.
- Tags migrate before releases.
- Release migration targets semver tags only: `vX.Y.Z`.
- `summary.json` keeps `schema_version: 2`.
- Retry guidance must use `gfrm resume`, not `gfrm migrate`.
- Exit code is `0` on success and non-zero on validation or operational failure.
- Raw tokens must never appear in logs, errors, output, fixtures, comments, or docs.
- Token precedence must remain deterministic:
  - `migrate`: settings `token_env`, then `token_plain`, then env aliases.
  - `resume`: session token context, then settings `token_env`, then `token_plain`, then env aliases.

## Architecture Boundaries

- `dart_cli/lib/src/cli.dart` delegates; it should not own business logic.
- `dart_cli/lib/src/application/` owns typed orchestration and preflight.
- `dart_cli/lib/src/migrations/` owns execution flow only.
- `dart_cli/lib/src/providers/` translates forge API calls.
- `gui/lib/src/application/` owns GUI contracts and value objects.
- `gui/lib/src/runtime/` bridges GUI contracts to `gfrm_dart` runtime.
- Flutter widgets should render state, not call runtime services directly.
- Prefer one public type per file, small helpers, explicit types, and `final` over `var`.
- Avoid runtime provider type dispatch such as `if (source is GitHubProvider)` in engine flow.

## PR Context Checklist

- For CLI/runtime changes, verify artifacts, exit codes, token precedence, resume behavior, and provider-pair
  invariants.
- For Flutter GUI changes, verify route behavior, Riverpod boundaries, widget state ownership, and focused widget/unit
  tests.
- For workflow/reviewer changes, verify fail-closed behavior, dedupe behavior, least-privilege permissions, and
  `scripts/*.test.mjs` coverage.
- For docs/user-facing changes, verify English and Portuguese docs stay aligned.
- If the PR only moves files or imports, avoid behavior comments unless a moved path breaks codegen, tests, or public
  imports.

## Path-Specific Rules

Apply these files when they match changed paths:

- `.github/instructions/dart-review.instructions.md`
- `.github/instructions/flutter-review.instructions.md`
- `.github/instructions/workflow-review.instructions.md`

## Comment Format

```md
[severity] Concrete problem.

Why: risk or regression.

Suggestion: specific fix.
```
