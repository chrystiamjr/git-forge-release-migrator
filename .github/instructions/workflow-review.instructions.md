---
applyTo: ".github/workflows/**/*.yml,.github/actions/**/*.yml,scripts/review-pr*.mjs,scripts/publish-pr-review.mjs"
---

# Workflow And Review Automation Rules

- Use `GH_TOKEN`, not `GITHUB_TOKEN`, for custom bot review and approval flows in this repository.
- The automated PR reviewer is the formal gate for `APPROVE` and `REQUEST_CHANGES`; Copilot review is advisory only.
- Approval must depend on required checks, not every visible status on the commit.
- Fail closed:
  - if analysis fails, keep producing a review artifact
  - publish step must still run and request changes rather than silently skipping
- Avoid duplicate or stale bot comments when rerunning on the same PR.
- Keep workflow behavior auditable and deterministic. Prefer a stable JSON result contract over implicit shell logic.
- Do not silently weaken branch protection, required checks, or review gating.
- Workflow changes should stay aligned with the repo quality gates in `.github/actions/quality-check/action.yml`.
- If review logic changes, update or add focused tests under `scripts/*.test.mjs`.
