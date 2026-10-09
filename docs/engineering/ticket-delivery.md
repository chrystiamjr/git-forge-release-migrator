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

## Project tracker configuration and direct links

Copy `ticket-worker-tracker.example.json` from this directory to the authorized workspace's ignored `.local/ticket-worker/tracker.json`. Its `validated` event is unmapped and its `done` event maps to Review: a generic local completion event can never move the canonical issue to Done. Do not commit the local config or credentials.

`scripts/ticket-pr-sync.mjs` implements project-specific `link`, `review` and `merge` operations. All are read-only/dry-run by default. Mutation needs both `--apply` and `ENABLE_YOUTRACK_SYNC=true`; the maintainer must authorize the workspace or workflow. Configure `GH_TOKEN` according to the repository account rule and `YOUTRACK_TOKEN` in the environment, never in files.

```bash
node scripts/ticket-pr-sync.mjs link 68
node scripts/ticket-pr-sync.mjs review 68
node scripts/ticket-pr-sync.mjs merge 68
```

The example PR number is illustrative. `link` creates/updates and reads back a compact PR association in YouTrack even when a state transition is already/skipped. `review` separately attempts forward-only Review. `merge` verifies current human review, successful configured checks and a real authorized human merge before Done; it does not merge PRs. Missing evidence keeps work open.

The trusted `.github/ticket-delivery.json` defines repository, host/project, human identities and required check names. Standalone maintenance PRs may explicitly include `Process plan: LOCAL-<slug>` instead of a tracker URL; never use this to omit the selected cloud ticket. Duplicate or other-author comment markers require reconciliation rather than overwriting another person's evidence.

Sync failures are visible and leave delivery pending; retry an event at most once, preserve the existing PR, then use the documented dry-run/reconciliation command. Historical completed checkpoints must be reconciled against the canonical issue; a stale local Done never overrides remote Review.

## Workflow activation and reviewer steps

After the workflow PR is human-reviewed and merged to main, the owner must configure repository secret `YOUTRACK_TOKEN` and variable `ENABLE_YOUTRACK_SYNC=true`. Give the token only needed issue/comment permissions for the allowlisted project. Do not paste it into PRs or commit files. Metadata-only workflows run default-branch code, never install or execute PR-head code with these credentials. Cloud linkage requires an authorized same-repository PR author; fork metadata alone cannot write YouTrack.

Observe the new checks, then require `test`, `ticket-validation`, `human-review` and `ticket-link` on main; retain resolved conversations and stale-review dismissal. Tighten admin bypass only after bootstrap works. The auxiliary bot intentionally ignores human/link gate contexts in its own opinion so it cannot deadlock solo review; those gates remain separately mandatory for merge and Done.

For each PR, personally review report, diff and applicable visual artifacts, then post `/reviewed <full-current-head-sha>` in GitHub. Post a new comment rather than editing an old decision. `/revoke-review <sha>`, deletion, edits or a new commit invalidates readiness. Merge manually once required checks are green. A decision posted after merge cannot retroactively satisfy automated pre-merge approval evidence.

The closed/merged event verifies immutable head, authorized human merger, effective pre-merge decision, successful latest GitHub Actions checks and resolved conversations before Done. Re-run the event workflow or the read-only `merge` reconciliation command after API outages; opt-in plus `--apply` is needed for mutations. Unknown/manual or backwards states stay untouched. Historical bootstrap work may require a separately documented owner decision; do not add a generic force/bypass completion flag.
