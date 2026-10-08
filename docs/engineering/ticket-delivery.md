# Ticket delivery

Read this document and [testing playbook](testing-playbook.md) before implementing a ticket. Project rules apply to any agent, including ticket-worker; no global skill modification is required.

## Lifecycle

`Backlog -> Develop -> Review -> Done`

- Select one ticket, verify canonical blockers, preserve existing work and agree scope.
- Define observable acceptance and record a comparable coverage baseline before code changes.
- Reproduce bugs, implement only authorized scope, run focused tests and review the changed/related code.
- Run the final project verification for an immutable commit. Passing local validation is **not Done**.
- Commit/push/open a PR only within authorization. Include a unique `YouTrack: https://<approved-host>/issue/GFRM-N` reference in the PR body.
- Verify a direct PR URL exists on YouTrack independently of state changes. Record the PR, current head SHA, checks and limitations in handoff.
- Leave the issue in **Review**. Checkpoint phase is `waiting_input`, not `completed`; dependencies remain blocked until canonical Done.
- Only human-reviewed current source plus a real authorized human merge to `main` can produce Done. PR closure without merge, bot approval and missing evidence do not qualify.

## Solo maintainer review

GitHub does not allow authors to approve their own PRs. The selected solo process uses the maintainer's explicit comment `/reviewed <full-current-head-sha>` after inspecting diff, acceptance evidence, coverage and applicable visual results. The maintainer then merges manually. This is human control, **not independent peer review**.

The agent must never write that decision, approve on behalf of the maintainer, enable auto-merge or perform merge. The bot provides diagnostic review; its APPROVED verdict alone cannot conclude work. New pushes, deleted/edited decisions and `/revoke-review <sha>` invalidate review readiness. Human identity checks establish the GitHub account, not who physically operated shared credentials: submit the decision yourself in GitHub.

Required checks must exist before branch protection requires them. Bootstrap under current protections with explicit manual review; enable the new checks after their workflows reach main. Repository secrets and protection changes need owner-approved setup. Maintain resolved-conversation and existing quality requirements.

## Handoff

Include ticket/PR links, branch, tested head/base SHAs, validation report, coverage comparison, review findings, actual Git actions, pending native/live checks and next human action. Never label widget simulations as native or real forge tests. Preserve previous evidence; do not overwrite another run or stage `.local`.

No backwards tracker transition is automatic. Unknown/manual states and outages require reconciliation, not invented completion. Link publication must remain independent even when a transition is already applied or skipped.
