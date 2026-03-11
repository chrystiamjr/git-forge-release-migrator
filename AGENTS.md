# AGENTS.md

High-signal context for coding agents working in this repository.

## Quick Start

1. Read `AGENTS.md` (this file) and `dart_cli/README.md` before touching code.
2. Run `yarn lint:dart && yarn test:dart` from the repo root before submitting any change.
3. All production code lives in `dart_cli/lib/src/`. Architecture map is below.
4. Check "Documentation Sync Rules" if you change any user-facing behavior.
5. Check "Known Pitfalls" and "Agent Constraints" before making structural decisions.

## Project

- Name: `git-forge-release-migrator`
- Public CLI command: `gfrm`
- Runtime: Dart-only
- Domain: migration of tags/releases/assets across Git forges with strong idempotency and retry behavior

## Scope

Supported cross-forge pairs:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> github` (Bitbucket Cloud)
- `gitlab -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> gitlab` (Bitbucket Cloud)

Out of scope:

- same-provider migrations
- Bitbucket Data Center / Server

## Current CLI Contract (v2)

Root command and subcommands:

- `gfrm migrate`
- `gfrm resume`
- `gfrm demo`
- `gfrm setup`
- `gfrm settings`

Settings actions:

- `init`
- `set-token-env`
- `set-token-plain`
- `unset-token`
- `show`

Important runtime behaviors:

- `--settings-profile` supported by `migrate` and `resume`
- token precedence must remain stable
- retry command in `summary.json` must use `gfrm resume`
- exit code `0` on success, non-zero on validation/operational failure

## Critical Business Invariants

1. Tags-first order:
- tags are migrated before releases
- release flow expects destination tags to exist unless `--skip-tags` is passed
- `--skip-tags` is only valid when destination tags already exist by other means; do not use it as a general shortcut

2. Semver-only release selection:
- selection currently targets `vX.Y.Z`
- non-semver tags are not selected for release migration

3. Idempotency and resume:
- terminal checkpoint states must prevent repeated work
- completed items are skipped
- incomplete items are retried

4. Bitbucket synthetic release model:
- represented by tag + notes + downloads + `.gfrm-release-<tag>.json`

5. Legacy Bitbucket behavior:
- missing manifest on source Bitbucket tag must not hard-fail by itself

## Artifact Contract

Each run writes under:

```text
migration-results/<timestamp>/
```

Required artifacts:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

`summary.json` expectations:

- schema is v2 (`schema_version: 2`)
- includes executed command metadata
- includes retry command when failures exist

## macOS Release Distribution

Release artifact names for macOS:

- `gfrm-macos-intel.zip`
- `gfrm-macos-silicon.zip`

macOS security mode (release workflow variable):

- `MACOS_RELEASE_SECURITY_MODE=permissive` (default): proceed with warnings when Apple signing/notarization credentials are missing
- `MACOS_RELEASE_SECURITY_MODE=strict`: fail macOS jobs when signing/notarization credentials are missing or notarization fails

Notarization credential support and precedence:

1. App Store Connect API key:
   - `APPLE_NOTARY_KEY_ID`
   - `APPLE_NOTARY_ISSUER_ID`
   - `APPLE_NOTARY_API_KEY_P8_BASE64`
2. Apple ID fallback:
   - `APPLE_NOTARY_APPLE_ID`
   - `APPLE_NOTARY_TEAM_ID`
   - `APPLE_NOTARY_APP_PASSWORD`

Required macOS architecture validation in CI:

- `gfrm-macos-intel` must produce `x86_64`
- `gfrm-macos-silicon` must produce `arm64`

Operational note:

- End users can run the compiled `gfrm` binary on a clean Mac without installing Dart/FVM/NVM/Yarn, as long as they download the correct architecture artifact and Gatekeeper requirements are satisfied (signed/notarized preferred; troubleshooting fallback may still be required).

## Auth and Security

Provider auth model:

- GitHub: `Authorization: Bearer <token>`
- GitLab: `PRIVATE-TOKEN` header
- Bitbucket Cloud: `Authorization: Bearer <token>`

Never log raw tokens.

Settings behavior to preserve:

- effective settings = deep merge of global + local
- profile resolution order:
  1. explicit `--settings-profile`
  2. `defaults.profile`
  3. `default`
- token precedence (`migrate`/`resume`) must remain deterministic and documented:
  - `migrate`: settings (`token_env`, then `token_plain`) -> env aliases
  - `resume`: session token context -> settings (`token_env`, then `token_plain`) -> env aliases
- hidden legacy overrides:
  - `--source-token`
  - `--target-token`
  - These flags still override token resolution when explicitly provided, but they are not part of the recommended public workflow.

## Architecture Map (Dart)

Main code lives in `dart_cli/lib/src/`.

- `cli.dart`
- `cli/settings_setup_command_handler.dart`
- `config.dart`
- `config/arg_parsers.dart`
- `config/validators.dart`
- `config/types/*`
- `models/runtime_options.dart`
- `models/migration_context.dart`
- `migrations/engine.dart`
- `migrations/selection.dart`
- `migrations/tag_phase.dart`
- `migrations/release_phase.dart`
- `migrations/summary.dart`
- `providers/registry.dart`
- `providers/{github,gitlab,bitbucket}.dart`
- `core/{http,checkpoint,jsonl,files,session_store,settings,versioning,logging}.dart`
- `core/exceptions/*`
- `core/types/*`

Provider adapters must produce canonical release data consumed by the engine.

## Safe Change Playbook

1. Read impacted flow first (`config`, `engine`, provider adapter, tests).
2. Identify all callsites and downstream consumers before changing a signature or type.
3. Preserve behavior for unaffected provider pairs.
4. Prefer additive/refactor-safe edits over broad rewrites.
5. Extract logic into small, single-responsibility helpers rather than expanding existing methods.
6. Run lint/analyze/tests before finalizing.
7. Keep docs and tests aligned with implementation.
8. Update `AGENTS.md` if the change affects CLI contract, invariants, or architecture.

## Engineering Rules for This Repo

Apply these rules to new and modified code:

1. Typing and declarations:
- avoid `var`
- prefer explicit typing
- prefer `final` when values do not change

2. File and class organization:
- avoid multiple classes in one file
- one class/type per file is preferred, especially under `core/types/`

3. Readability:
- keep spacing and block structure clear
- avoid dense `if` chains and tightly packed control flow
- prefer small helpers with single responsibility

4. Complexity ceilings:
- no method above 120 lines
- no orchestration file above 500 lines

5. Engine flow:
- avoid main-flow dispatch by runtime type checks (`if (source is ...)` / `if (target is ...)`)
- keep provider-specific rules in adapters

6. Design principles:
- follow Single Responsibility: each class/function does one thing
- follow Open/Closed: extend behavior via new classes or abstractions, not by modifying existing ones
- follow Liskov Substitution: subtypes must be substitutable for their base types
- follow Interface Segregation: prefer narrow interfaces over fat ones
- follow Dependency Inversion: depend on abstractions, not concrete implementations
- apply DRY: extract shared logic as soon as it appears in 2+ real callsites; do not extract speculatively
- follow Clean Architecture layer boundaries: core has no dependency on providers or CLI; providers depend only on core abstractions

7. Anti-patterns to avoid:
- no god classes (classes with unrelated responsibilities)
- no deep nesting (max 3 levels of indentation)
- no magic strings or numbers — use named constants
- no premature abstraction — extract only when 2+ real callsites exist
- no circular dependencies between layers (core ← migrations ← providers ← cli)
- no multi-class files (one class/type per file)
- no large files beyond complexity ceilings defined above

## Formatting and Tooling

- line width: `120`
- Dart/Flutter SDK pinned by `.fvmrc` (`3.41.0`)
- Node.js version pinned by `.nvmrc` (`22.14.0`) — use `nvm use` or match it manually
- use Husky hooks for local quality gates

Primary local commands (from repo root):

```bash
yarn lint:dart
yarn test:dart
```

Coverage workflow:

- `yarn coverage:dart` generates `dart_cli/coverage/lcov.info` and `dart_cli/coverage/html/`
- `yarn coverage:dart` also packages `dart_cli/coverage/coverage_html.zip` via a Node script shared with CI expectations
- CI publishes `dart_cli/coverage/coverage_html.zip` alongside `dart_cli/coverage/lcov.info`
- coverage threshold is `80%`, enforced with `coverde`
- `yarn coverage:dart` is part of the expected local validation flow and should pass before finalizing changes

Equivalent direct commands (inside `dart_cli`, use as fallback/debug):

```bash
fvm dart format -l 120 --set-exit-if-changed bin lib test
fvm dart analyze
fvm dart test
```

## Test Strategy

Test layout:

- `dart_cli/test/unit/**`
- `dart_cli/test/feature/**`
- `dart_cli/test/integration/**`

When changing behavior:

- add/update unit tests for granular logic
- add/update feature tests for CLI and flow-level behavior
- add/update integration tests for end-to-end invariants
- keep terminal I/O at the production edge; tests should prefer in-memory output/input adapters over real `stdout/stderr/stdin`
- for CLI and logger tests, assert captured sink content instead of relying on terminal output side effects

Minimum coverage priorities:

- CLI parsing and validation
- settings profile/token resolution
- provider URL parsing and canonical mapping
- checkpoint terminal-state semantics
- retry generation and summary consistency
- idempotency + failed-tags behavior

Current quality gate implementation:

- main quality gate logic lives in `.github/actions/quality-check/action.yml`
- primary workflows are `.github/workflows/quality-checks.yml` and `.github/workflows/release.yml`
- `.github/workflows/quality-checks.yml` runs on `pull_request`
- `.github/workflows/release.yml` runs on `push` to `main`
- there is no manual `workflow_dispatch` path for the main quality-check or release pipelines

Run a specific test file (inside `dart_cli`):

```bash
fvm dart test test/unit/path/to/test.dart
```

## Documentation Sync Rules

If command contract, auth model, support matrix, or output artifacts change, update all:

- `README.md`
- `docs/pt_br/README.md`
- `docs/en_us/USAGE.md`
- `docs/pt_br/USAGE.md`
- `dart_cli/README.md`

## Commit Message Conventions

All commits must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

### Format

```
<type>(<scope>): <short imperative summary>

- Bullet describing what changed and why (not how)
- One bullet per logical concern; group related changes under one bullet
- Keep bullets focused: what was broken/missing, what was done, why it matters
```

### Types

| Type | When to use | Triggers release |
|------|-------------|-----------------|
| `feat` | New capability or behavior visible to users or downstream code | minor |
| `fix` | Corrects a bug or wrong behavior | patch |
| `perf` | Performance improvement with no behavior change | patch |
| `refactor` | Internal restructuring with no behavior change | patch |
| `test` | Adds or updates tests only (no production code change) | patch |
| `chore` | Tooling, config, dependency bumps, or housekeeping | patch |
| `build` | Build system or compilation changes | patch |
| `style` | Formatting or whitespace only | patch |
| `docs` | Documentation, comments, or guide-only changes | **none** |
| `ci` | CI/CD workflow or pipeline changes | **none** |

### Scopes

| Scope | Covers |
|-------|--------|
| `dart` | Dart production source (`dart_cli/lib/`) |
| `ci` | GitHub Actions workflows, quality gates, release pipeline |
| `docs` | Markdown documentation, README, AGENTS, CHANGELOG |
| `deps` | Dependency updates (`pubspec.yaml`, lock files, Dependabot) |
| `release` | Semantic-release config, changelog generation, versioning |

### Rules

1. Use imperative mood in the summary line: "add retry logic", not "added" or "adds".
2. Summary line must be 72 characters or fewer.
3. Each bullet must describe **what** changed and **why**, not the implementation detail.
4. Group tightly related changes into one bullet; avoid one bullet per file.
5. Do not add a co-author trailer unless explicitly requested.
6. Keep the subject line free of punctuation at the end.
7. `docs` and `ci` commits do **not** trigger a release. For a `chore` that should also not release (e.g. adding a tooling file with no product impact), append `[skip ci]` to the commit message.

### Examples

```
feat(dart): improve HTTP resilience and diagnostic logging

- Apply exponential backoff to requestJson() using existing helper
- Add 1-retry with 500ms delay to requestStatus() before returning 0
- Surface diagnostic warnings for corrupt checkpoint and malformed settings
```

```
test(dart): add unit and integration tests for migration pipeline

- Add 12 unit tests for TagPhaseRunner covering dry-run, auth errors, and checkpoints
- Add 11 unit tests for ReleasePhaseRunner covering publish, skip, and concurrent workers
- Add 5 integration tests for MigrationEngine covering full and failure flows
```

```
fix(dart): rethrow AuthenticationError from tag phase without wrapping

- MigrationPhaseError was incorrectly catching AuthenticationError
- Auth failures must propagate immediately so callers can surface them to the user
```

---

## Handling PR Review Comments

When asked to address review comments on an open PR, follow these steps in order.

### 1. Fetch all inline comments

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api \
  repos/<owner>/<repo>/pulls/<pr_number>/comments
```

Read each comment carefully and classify it before touching code:

| Class | Action |
|-------|--------|
| **Clear bug / correct suggestion** | Fix the code, then reply with what was changed and why. |
| **Style / naming preference** | Apply if it aligns with engineering rules in this file; reply confirming. |
| **Breaking change** | Do NOT apply in the same PR. Reply explaining the trade-off and state that it will be tracked as a follow-up issue. |
| **Pre-existing issue flagged by the review** | Reply acknowledging the concern, explain what this PR already does to mitigate it (if anything), and propose a follow-up. |

### 2. Apply code fixes

Make all applicable fixes. Run lint and tests before committing:

```bash
yarn lint:dart && yarn test:dart
```

### 3. Commit and push

Use a single commit that references the review:

```
fix: address PR review comments

- <one bullet per fix, explaining what was wrong and what was changed>
```

Push to the same branch — the open PR picks it up automatically:

```bash
git push origin <branch>
```

### 4. Reply to each comment individually

Use the GitHub API to reply inline (not as a top-level PR comment):

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api \
  repos/<owner>/<repo>/pulls/<pr_number>/comments/<comment_id>/replies \
  -f body="<your reply>"
```

Reply guidelines:
- For **fixed** comments: confirm what was changed and in which commit.
- For **deferred** comments: acknowledge the concern, explain why it is not addressed in this PR, and state the next step (follow-up issue, separate PR, etc.).
- Keep replies factual and concise. Do not repeat the original comment — go straight to the resolution.

### 5. Resolve all threads

Get the GraphQL thread IDs:

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api graphql -f query='
{
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <pr_number>) {
      reviewThreads(first: 20) {
        nodes {
          id
          isResolved
          comments(first: 1) { nodes { databaseId } }
        }
      }
    }
  }
}'
```

Resolve each thread (replace `<thread_id>` with the `id` from the query above):

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api graphql -f query="
  mutation {
    resolveReviewThread(input: { threadId: \"<thread_id>\" }) {
      thread { id isResolved }
    }
  }"
```

---

## Pull Request Template

Use this structure for every PR opened against `main`. All sections except "Additional Notes" are required.

```markdown
## Summary

<!-- One to three sentences: what this PR does and why it exists. -->

## Context

<!-- What was the state before this PR?
     Why is this change needed now?
     Link related issues, tickets, or previous PRs if relevant. -->

## What Changed

<!-- Bullet list of the logical changes grouped by concern.
     Focus on behavior and structure, not file names.
     Each bullet should be readable without opening the diff. -->

- **<Area or component>:** <description of change and rationale>

## Why It Matters

<!-- What problem does this solve?
     What risk does it remove?
     What capability does it add?
     Keep it concrete — avoid vague statements like "improves quality". -->

## Expected Results

<!-- What should reviewers verify?
     Include test commands, expected output, or behavioral checkpoints. -->

```bash
# Run tests
yarn test:dart

# Example output
All tests passed.
```

## Additional Notes

<!-- Optional. Use for:
     - Known limitations or follow-up work
     - Risky areas reviewers should pay extra attention to
     - Migration or deployment notes
     - Anything that doesn't fit above -->
```

---

## Known Pitfalls

- Do not call provider APIs directly from `engine.dart` — use provider adapters.
- Do not add runtime type dispatch (`if (source is X)` / `if (target is X)`) in engine flow — keep it in adapters.
- Bitbucket downloads and `.gfrm-release-<tag>.json` are part of the same atomic synthetic release — always treat them together.
- `summary.json` schema version must stay at `2` unless an explicit versioning decision is made.
- Missing Bitbucket manifest on a source tag must not cause a hard failure — this is a legacy compatibility rule.
- Never log raw tokens anywhere in the codebase.

## Agent Constraints

- Do not introduce new top-level CLI commands without updating the CLI Contract section in this file.
- Do not change token precedence order without updating both code and all documentation files listed in "Documentation Sync Rules".
- Do not bypass or weaken the `--skip-tags` safety check in release phase logic.
- Do not expand release selection beyond semver (`vX.Y.Z`) — this is an explicit non-goal for the current phase.
- Do not add Bitbucket Data Center / Server support — out of scope.

## Non-Goals (Current Phase)

- same-provider migrations
- Bitbucket Data Center compatibility
- expanding release selection beyond current semver-only behavior
