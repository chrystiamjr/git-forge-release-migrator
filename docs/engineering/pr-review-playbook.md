# PR Review Playbook

Use this flow when asked to address inline review comments on an open PR.

## Automated reviewer

`scripts/review-pr.mjs` runs two layers after Quality Checks:

- **Hard rules** (secrets, contract invariants, EN/PT-BR docs sync, layer imports): deterministic. Secrets are
  `[critical]`, the other blocking rules `[important]`, and their notes `[suggestion]`.
- **AI review** (`scripts/ai-review.mjs`, prompt in `scripts/ai-review-prompt.md`): reads the patch plus the full
  post-change file, `AGENTS.md`, and the matching `.github/instructions/*`. Fuzzy heuristics (long method, `setState`,
  test gaps, …) are sent as hints that the model confirms or dismisses; posted without the model, they are
  `[suggestion]`.

Only `[critical]`, `[bug]`, and `[important]` block a merge. `[suggestion]` and `[question]` are plain comments.

The AI layer is opt-in and owner-only: set repo variable `AI_REVIEW_ENABLED=true`; it then runs only on PRs authored
and triggered by the repository owner. PR content is untrusted prompt input, so the gate limits prompt-injection exposure and
subscription quota use. Other contributors' PRs get the hard rules plus hints; review those locally with your own
tooling. The workflow runs the review scripts from the default branch, so reviewer changes take effect after merge. Set `AI_REVIEW_ENABLED=false` (or delete it) to turn it off.

| Engine (`AI_REVIEW_ENGINE`) | Credential | Optional variables |
|---|---|---|
| `claude` (default) | secret `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token` | `CLAUDE_MODEL` (unset = routed, see below; set = pinned), `CLAUDE_EFFORT` (default `medium`, only with `CLAUDE_MODEL`) |
| `gemini` | secret `GEMINI_API_KEY` (paid quota) | `GEMINI_MODEL` (default `gemini-flash-latest`), `GEMINI_THINKING_LEVEL` (default `high`) |

Claude runs headless with all tools disabled, from an empty directory, without GitHub or Gemini credentials in its
environment. The review body records the engine, model, and resolved model version. If the engine fails, the review
fails closed with `llm_review_unavailable`; re-run the workflow.

### Optional source verification

`AI_REVIEW_VERIFICATION_MODE` defaults to `off`. `shadow` records a candidate verification result in
the analysis artifact while preserving baseline publication; `enforce` publishes only substantiated
AI findings. Deterministic rules are never filtered. The verifier uses Claude Code `2.1.296`,
Sonnet/medium and subscription OAuth in a temporary home with only Read/Grep/Glob tools. It reads a
data-only snapshot of the exact PR head, including unchanged callers and tests. Links, executable
permissions and Claude configuration are not restored from the archive. Source citations must match
real lines before a claim is accepted. This validates cited text, not the model's reasoning by itself.

One pass covers findings, prior assessments and test requirements, with a three-minute deadline
including setup. It remains part of the same AI round. Live PR/head guards run before and during the
pass and before publication. In `enforce` mode, verifier failure publishes no new AI claims, adds no readiness blocker,
and cannot clear existing AI blockers. It produces a counted COMMENT rather than a clean approval
when no blocker remains. In `shadow` mode, verifier failure leaves the baseline findings and verdict unchanged
and does not qualify as a complete shadow observation. Initial detector failure retains the existing fail-closed
behavior. In enforce mode, rejected/inconclusive candidates remain in the artifact rather than new inline comments.

The [benchmark and rollout procedure](review-benchmark/README.md) requires confirmed labels and five
real PRs in shadow before human promotion to `enforce`. Effortless has a separate pinned, isolated
experiment adapter; it is not installed in production. Its initial static compatibility check failed.
The existing model router remains active. Roll back verification independently by setting its mode to `off`.

Unless `CLAUDE_MODEL` is set, the claude engine routes each PR by tier (`scripts/ai-review-triage-prompt.md`):
docs-only PRs (`website/**`, `README.md`) go straight to `light`; otherwise a Haiku call at effort `low` reads the
patches and picks `light` (haiku, `low`), `standard` (sonnet, `medium`), or `deep` (opus, `medium`). If triage fails,
the review uses `standard`. The review footer shows the chosen tier, its reason, and the combined cost.

Each run loads the verified bot's review threads, including resolved/outdated threads, original locations and
replies from the PR author or repository owner. Both threads and replies are paginated. Stable finding IDs,
stored in hidden comment metadata, keep the same concern attached to its original discussion even when its
wording, severity, line or filename changes. Existing comments use their GitHub comment IDs for compatibility.
Two different causes in one symbol remain separate findings; proximity alone never suppresses a finding.

The model assesses prior findings against current code. Outstanding findings keep blocking without another
inline comment; review summaries link to their discussions. A change of assessment or severity gets one reply
in the original thread. Resolved threads and human claims of a fix are not proof; omitted/uncertain assessments
retain outstanding blockers. A verified bot assessment of `fixed` or `answered` survives an omitted reassessment
in every mode. An explicit `applicable`/`uncertain` assessment or a new linked finding can reopen it; enforce mode
still requires verifier support for new assessments/findings. History failures cannot silently clear outstanding
blockers. Replies are reconsidered on the next push or
manual review rerun, without triggering an extra AI call immediately.

Unknown finding IDs, duplicate assessments, and contradictory finding/assessment pairs invalidate the AI result.
The production caller publishes a blocking `llm_review_unavailable` finding containing the reason and rerun
instruction; deterministic checks and hints remain. This is intentional: silently relabeling an unknown ID as a
new concern can duplicate a discussion or detach it from its history. Failed rounds do not consume a completed
AI-round allowance. Re-run after correcting the cause rather than treating an invalid result as an approval.

Reusable lessons belong in `.github/instructions/review-lessons.instructions.md`. Promote an accepted finding
or corrected false positive through a normal documentation PR with maintainer review and merge. Each entry
includes scope, guidance, exceptions, and a permanent source-thread link. Only the trusted default-branch copy
is loaded; discussions never automatically become repository policy.

### One required-tests checklist

The metadata-only PR Review Lifecycle workflow creates one bot-owned **Required tests** comment on open/reopen,
including draft PRs, and refreshes its scope on pushes. It runs trusted default-branch scripts; it never executes
PR-head code. When Quality Checks completes, a separate evidence job updates that comment before AI analysis.
The review publisher merges additional scenarios into the same comment before publishing its verdict. Reviews
link to the checklist instead of repeating a "Tests needed" section.

The checklist uses existing validation scope rules. Passing rows link to the CI run/job; failed, cancelled,
skipped, missing, or delegated evidence stays unchecked with its status. Native/live acceptance remains separate
and CI delegation is not a pass. This comment is informational and does not introduce a new merge gate.
Checklist or evidence API failures are logged and cannot suppress analysis or verdict publication. When evidence
cannot be collected, test rows stay pending and the review reports that the checklist may be incomplete.

Validation reports include PR head/base, tested revision, workflow run/attempt, and named test results. PR validation
derives its base from the tested merge's first parent and verifies the PR head is its second parent. The reader
requires the current PR revision and latest CI attempt; a synthetic merge commit must have the current head and
live target-branch Git ref as its parents. The PR/event base snapshot can be stale after target-branch pushes.
An identity mismatch leaves rows pending with a revision-evidence explanation; it must never be repaired by
manually ticking boxes. For AI-requested scenarios, a green suite is insufficient: the reviewer must inspect a test
implementation and name the exact test that passed. Missing/skipped tests remain pending. Verified obsolete
requirements can be withdrawn with a stated reason; failures to review do not remove prior requirements.

The lifecycle, evidence, and publication jobs share a per-PR publication concurrency group. Writers re-read the
current comment, edit only the verified bot's copy, and skip identical updates. New heads invalidate previous
checkmarks. Only evidence relevant to listed scenarios is retained in comment metadata, not the full test inventory.
The shared writer group uses `queue: max` so pending lifecycle/evidence jobs cannot replace a queued publisher
([GitHub concurrency rules](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)).
Changes to those workflows also trigger **Review Queue Validation** on the PR: three harmless matrix jobs share
an isolated queue. All three must finish successfully before accepting the scheduler evidence; this exercises
GitHub's parser and queue without running privileged review code from the PR or accessing secrets.
Process and translation checks come from the bound validation report, not legacy CI step names.

If setup, analysis, or artifact transfer leaves no valid result, trusted recovery creates a blocking verdict bound
to the triggering PR/head after checking live state. Existing valid results (including explicit skips) are retained;
cancelled workflows do not recover or publish, and closed or superseded PRs are skipped.

### Closure and stale results

Eligibility is checked before AI tooling setup and again before model calls and publication. Closing or merging
a PR triggers a small cancellation job for queued/running review workflows. Every publication, dismissal,
checklist edit and label change also checks live PR state and the reviewed head. Stale or closed work is skipped.
Cancellation queries only active statuses (`queued`, `in_progress`, `requested`, `waiting`, `pending`) and collects
matching run IDs before cancelling them, so mutations do not shift the remaining pages. Completed history is not scanned.
Already-in-flight API calls cannot be recalled; cancellation and write guards prevent further work once closure
is observed. New verdicts are published before older bot verdicts are dismissed.

Bot credentials need pull-request read/write plus Actions read for validation artifacts. Only the cancellation
job uses the workflow token with Actions write. An unresolved bot identity stops publication rather than trusting
another author's marker. Review scripts/workflows take effect after they are merged into the default branch;
validate their fixtures locally first and observe a disposable PR after human merge.

Each PR gets at most `AI_REVIEW_MAX_ROUNDS` AI rounds (default 3); later pushes get the deterministic rules only.
To buy one more round, add the `ai-review` label and re-run the Automated PR Review workflow; the bot removes the label
after using it. Draft PRs get no AI round until they are marked ready for review. While AI is deferred (draft or
limit), a last AI round that found blocking issues keeps the PR blocked with `llm_review_pending` until another AI round
verifies the fixes. Every completed AI round leaves a review carrying its round marker, a COMMENT when checks are still
pending, and only reviews written by the bot identity (`REVIEW_BOT_LOGIN`, resolved by the workflow) count. A run that finds the PR merged or
closed, before reviewing or before publishing, posts nothing.

## 1. Fetch inline comments

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api \
  repos/<owner>/<repo>/pulls/<pr_number>/comments
```

Classify each comment before editing:

| Class | Action |
|-------|--------|
| Clear bug or correct suggestion | Fix it now |
| Style or naming preference | Apply if aligned with repo rules |
| Breaking change | Defer to follow-up |
| Pre-existing issue | Acknowledge and propose follow-up |

## 2. Apply fixes and validate

Run the standard quality gates after making applicable changes:

```bash
yarn lint:dart
yarn test:dart
yarn coverage:dart
```

## 3. Commit and push

Use one commit for the review round and push to the same branch:

```bash
git push origin <branch>
```

## 4. Reply inline to each handled comment

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api \
  repos/<owner>/<repo>/pulls/<pr_number>/comments/<comment_id>/replies \
  -f body="<reply>"
```

Reply guidelines:

- fixed comments: say what changed and in which commit
- deferred comments: explain why they are out of scope for this PR and what the follow-up is
- keep replies factual and concise

## 5. Resolve review threads

Fetch thread IDs:

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

Resolve a thread:

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api graphql -f query="
  mutation {
    resolveReviewThread(input: { threadId: \"<thread_id>\" }) {
      thread { id isResolved }
    }
  }"
```


## Ticket delivery

Apply [ticket delivery](ticket-delivery.md) and [testing playbook](testing-playbook.md) after fixes. New commits invalidate the previous human review decision. Bot approval is auxiliary; leave the linked ticket in Review until the human-reviewed current head is manually merged. Never impersonate the maintainer or merge through ticket-worker.
