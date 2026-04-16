---
applyTo: ".github/workflows/**/*.yml,.github/actions/**/*.yml,scripts/review-pr*.mjs,scripts/publish-pr-review.mjs,scripts/*.test.mjs"
---

# Workflow And Review Automation Rules

- Use `GH_TOKEN`, not `GITHUB_TOKEN`, for custom bot review and approval flows in this repository.
- The automated PR reviewer is the formal gate for `APPROVE` and `REQUEST_CHANGES`; Copilot review is advisory only.
- Approval must depend on required checks, not every visible status on the commit.
- If review logic changes, update or add focused tests under `scripts/*.test.mjs`.

## Fail-Closed Principle

- If analysis fails, keep producing a review artifact.
- Publish step must still run and request changes rather than silently skipping.
- Missing review result file triggers a fallback `request_changes` verdict.
- Never let a workflow failure path result in an implicit approval or skip.

## Determinism and Auditability

- Keep workflow behavior auditable and deterministic.
- Prefer a stable JSON result contract over implicit shell logic.
- Do not silently weaken branch protection, required checks, or review gating.
- Workflow changes should stay aligned with the repo quality gates in `.github/actions/quality-check/action.yml`.
- Avoid duplicate or stale bot comments when rerunning on the same PR.

## Shell Safety Heuristics

Flag when you see:

- Unquoted variables in shell steps: `$VAR` instead of `"$VAR"` — word splitting risk.
- Missing error propagation: shell steps without `set -e` or explicit error checking.
- `echo` of secrets or tokens to stdout/logs — must use `::add-mask::` or avoid entirely.
- Inline scripts over 30 lines — extract to a script file for testability.
- `curl` or `wget` without error checking (`--fail`, `-f`) — silent failures on HTTP errors.
- `cd` without checking return code — subsequent commands run in wrong directory.

## Workflow Structure Heuristics

Flag when you see:

- `GITHUB_TOKEN` used where `GH_TOKEN` (bot token) is required — wrong identity for reviews.
- `continue-on-error: true` without downstream handling of the failure — swallows errors.
- Workflow `permissions` broader than needed — principle of least privilege.
- Missing `concurrency` group on workflows that should not run in parallel per PR.
- Hard-coded action versions without SHA pinning — supply chain risk.
- New secrets referenced but not documented in workflow comments or README.
- Workflow dispatch inputs without validation or defaults.
- Conditional steps using string comparison without quoting: `if: steps.x.outputs.y == true` instead of `if: steps.x.outputs.y == 'true'`.

## Review Script Heuristics (review-pr.mjs / publish-pr-review.mjs)

Flag when you see:

- New finding rule without corresponding test in `*.test.mjs`.
- Finding severity that does not match `blocking` or `note` — must be one of these two.
- GitHub API calls without error handling — must handle rate limits and auth failures.
- Pagination logic that assumes `<= 100` results — must loop.
- Marker string (`<!-- auto-pr-review -->`) changed without updating both scripts.
- New `TARGETED_TEST_GROUPS` or `CONTRACT_DOC_GROUPS` entry without signal patterns — will always trigger.
- Regex patterns without escaping special characters in user-controlled content.

## Quality Gate Alignment

The quality-check composite action runs these in order:
1. Translation parity
2. Reviewer script tests (`yarn test:reviewer`)
3. Dart lint (120 char lines)
4. Flutter lint and analysis
5. Flutter unit tests
6. Dart test coverage (80% threshold)

Any workflow change must not break or bypass this sequence. If adding a new gate, insert it in the appropriate position.
