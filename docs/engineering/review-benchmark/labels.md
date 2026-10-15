# Review benchmark labeling sheet

Status: proposed labels accepted by chrystiamjr on 2026-10-12. No model trials or benchmark pass claimed.

Confirm `confirmed_label` for each case and set `confirmed_by` in `cases.json`. Allowed labels: `false_positive`, `real_bug`, `clean`. Correct or replace disputed examples first. The six proposed false positives include a policy disagreement; the two Dio cases are correlated. Twelve cases are a pilot, not a representative accuracy estimate.

Clean controls cover only the named concern. Later replies and rationale below are adjudication evidence and must never enter model prompts. Prompts use immutable base/head code with a neutral title because historical PR-description revisions are unavailable.

## case-01: false_positive
PR #73; `dart_cli/lib/src/core/http.dart`; head `3ae1cf5d23ba01c14840ca23b87a0fe9b6a3e5a8`.

<!-- auto-pr-review -->
[question] The fail-fast check and the 'HTTP <status>' message only run when Dio returns a non-2xx Response. If the DioAdapter instance keeps Dio's default validateStatus (reject codes >= 300), every 404/409/422 arrives as a DioException. That branch still retries every non-401/403 status and sets `lastError = exc.message`, which has no `HTTP 409`. requestJson doesn't pass its own validateStatus, and the new tests use a fake Dio that returns responses directly. Please confirm DioAdapter sets `validateStatus: (_) => true`. Otherwise, apply `_isRetryableStatus` and the status prefix in the DioException branch too.

Symbol: `requestJson`

Why: If so, the claimed fail-fast and 409 'already exists' matching never happen against real forges.

Proposed rationale: DioAdapter already configures validateStatus to return true (line 12). The claimed production-default behavior does not apply.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/pull/73#discussion_r4233557912) · [source 2](https://github.com/chrystiamjr/git-forge-release-migrator/blob/3ae1cf5d23ba01c14840ca23b87a0fe9b6a3e5a8/dart_cli/lib/src/core/adapters/dio_adapter.dart)

## case-02: false_positive
PR #73; `dart_cli/lib/src/core/http.dart`; head `88f68317854208f89ba4d09fe8c918aa8713d61b`.

<!-- auto-pr-review -->
[question] The fail-fast branch only runs if Dio returns 4xx as a Response. `requestJson` doesn't set `validateStatus`; if DioAdapter keeps Dio's default (throw on 4xx), production 404/409/422 go through the `DioException` branch, which still retries and whose `lastError` (exc.message) lacks the status. Is validateStatus relaxed in DioAdapter? If not, apply `_isRetryableStatus` in the DioException branch too and include the status in the message.

Symbol: `requestJson`

Why: If not, the stated 'fail on first try' and '409 check can now match' fixes don't happen in production; the new tests use a fake Dio that returns Responses and can't detect this.

Proposed rationale: Repeated validateStatus concern; unchanged DioAdapter already accepts non-2xx responses. Correlated with case 01.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/pull/73#discussion_r4235146468) · [source 2](https://github.com/chrystiamjr/git-forge-release-migrator/blob/88f68317854208f89ba4d09fe8c918aa8713d61b/dart_cli/lib/src/core/adapters/dio_adapter.dart)

## case-03: false_positive
PR #73; `dart_cli/lib/src/core/http.dart`; head `88f68317854208f89ba4d09fe8c918aa8713d61b`.

<!-- auto-pr-review -->
[question] The PR says the existing `409` 'already exists' check can now match because messages include the HTTP status. That check isn't in this diff. Which caller relies on it, and is there a test that drives it through the real requestJson path?

Symbol: `requestJson`

Why: Re-run behaviour depends on this match: without it, already-existing tags may be counted as failures.

Proposed rationale: TagPhase line 320 matches HTTP 409/already exists and falls back to checking the destination tag.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/pull/73#discussion_r4235146333) · [source 2](https://github.com/chrystiamjr/git-forge-release-migrator/blob/88f68317854208f89ba4d09fe8c918aa8713d61b/dart_cli/lib/src/migrations/tag_phase.dart)

## case-04: false_positive
PR #73; `scripts/ai-review.mjs`; head `3ae1cf5d23ba01c14840ca23b87a0fe9b6a3e5a8`.

<!-- auto-pr-review -->
[suggestion] Timeouts are now retried. With a 180 s timeout per attempt, 4 attempts plus backoff can take about 12.2 minutes before failing closed. The catch also retries any thrown error, not only network or abort errors. Check that the workflow timeout covers this worst case, or cap retries for TimeoutError, and limit retries to TypeError and AbortError/TimeoutError.

Symbol: `callGemini`

Why: If this runs longer than the job timeout, the job is killed instead of producing the llm_review_unavailable artifact, which bypasses the fail-closed path.

Proposed rationale: The workflow has no short job timeout; the retry duration fits its default. Proposed label needs human confirmation for the broader retry-policy suggestion.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/pull/73#discussion_r4233558142) · [source 2](https://github.com/chrystiamjr/git-forge-release-migrator/blob/3ae1cf5d23ba01c14840ca23b87a0fe9b6a3e5a8/.github/workflows/auto-pr-review.yml)

## case-05: false_positive
PR #73; `scripts/ai-review-triage-prompt.md`; head `88f68317854208f89ba4d09fe8c918aa8713d61b`.

<!-- auto-pr-review -->
[suggestion] Triage reads untrusted PR title, body and patches, and its choice lowers review depth. A crafted PR could push Haiku toward `light`. Consider a floor (never below `standard` when any file outside docs changes), or derive the tier from deterministic path rules first.

Why: The triage step can weaken the review gate; the owner-only gate limits but doesn't remove this.

Proposed rationale: Owner explicitly accepted routing risk and rejected a standard-tier floor. This is an accepted-policy suggestion, not a disproven security property; confirm whether to count as nonactionable.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/pull/73#discussion_r4235146596) · [source 2](https://github.com/chrystiamjr/git-forge-release-migrator/blob/88f68317854208f89ba4d09fe8c918aa8713d61b/.github/workflows/auto-pr-review.yml)

## case-06: false_positive
PR #73; `dart_cli/lib/src/providers/github.dart`; head `3cd2ace6abbb80190daef2a272cf8c0f3fdccfa7`.

<!-- auto-pr-review -->
[question] When the tag lookup fails (e.g. a draft release whose tag does not exist yet) and `target_commitish` is a branch name, this now rethrows `HttpRequestError` where it used to return a value. The tag phase is not in this diff: does it catch this and mark the tag failed, or does the exception abort the run before `summary.json` and the retry command are written?

Symbol: `resolveCommitShaForMigration`

Why: If it aborts the run, the artifact-contract breakage this PR fixes for the release phase comes back in the tag phase for GitHub sources.

Proposed rationale: TagPhase _resolveCanonicalAndCommit catches non-authentication errors and returns an empty SHA; _handleMissingCommit records a failed tag.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/pull/73#discussion_r4235346217) · [source 2](https://github.com/chrystiamjr/git-forge-release-migrator/blob/3cd2ace6abbb80190daef2a272cf8c0f3fdccfa7/dart_cli/lib/src/migrations/tag_phase.dart)

## case-07: real_bug
PR #74; `scripts/review-pr.mjs`; head `7a86db245dbf9311914575288ccb73680ddfaac9`.

<!-- auto-pr-review -->
[important] Once the cap is reached, the next push runs only the deterministic rules. If those find nothing and checks are green, the verdict is `approve`, and `publish-pr-review.mjs` dismisses the earlier AI `REQUEST_CHANGES` review (`dismissPreviousReviews`). Unresolved critical or important AI findings from the last AI round are therefore silently replaced by a bot approval, and the job passes. Fix: when the gate is closed by the round limit, never upgrade to `approve`. Either emit `wait` or a non-approving COMMENT, or keep `request_changes` while the latest AI round still has blocking findings. Alternatively, skip dismissing earlier AI reviews in that case.

Symbol: `resolveAiReviewGate`

Why: Pushing past the cap turns blocking AI findings into an automatic approval. That silently weakens review gating, which the workflow rules forbid.

Proposed rationale: The historical round-cap path can replace an earlier blocking AI verdict with approval; fixed in f38f4a5.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/pull/74#discussion_r4235384530) · [source 2](https://github.com/chrystiamjr/git-forge-release-migrator/blob/7a86db245dbf9311914575288ccb73680ddfaac9/scripts/review-pr.mjs)

## case-08: real_bug
PR #74; `scripts/publish-pr-review.mjs`; head `9a63b5052f25ecad80b6ed4bc963433d06d8650e`.

<!-- auto-pr-review -->
[suggestion] `AI_REVIEW_BLOCKING_MARKER` is added whenever the overall verdict is `request_changes` and the LLM completed, even when only a deterministic hard finding (e.g. `missing_pt_br_doc_sync`) blocked and the AI found nothing blocking. After the round limit, `buildPendingAiFinding` then keeps the PR blocked with `llm_review_pending` ('The last AI review round found blocking issues…') after the hard issue is fixed, so the only way out is a paid label round. Fix: have `runReview` record whether the LLM's own findings were blocking (e.g. `llm.blocking = true`) and add the marker only from that flag.

Symbol: `buildReviewBody`

Why: This over-blocks: it wastes a paid AI round and shows a misleading reason, though it fails safe.

Proposed rationale: The historical publisher tags deterministic-only blocking as AI blocking; fixed in 972d972.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/pull/74#discussion_r4235842693) · [source 2](https://github.com/chrystiamjr/git-forge-release-migrator/blob/9a63b5052f25ecad80b6ed4bc963433d06d8650e/scripts/publish-pr-review.mjs)

## case-09: real_bug
PR #74; `scripts/review-pr.mjs`; head `f38f4a5bfc6efaf32287785b704ebcaa687ab531`.

<!-- auto-pr-review -->
[suggestion] When the AI ran and the verdict is `wait` (no blocking findings, required checks not green), `publishReviewResult` posts nothing. The `auto-pr-review:llm` marker is therefore never written and the round is not counted. The extra-round label is still removed. Consider publishing a COMMENT review that carries the marker whenever the LLM ran, or only consume the label and count the round once a review was actually published.

Symbol: `runReview`

Why: Paid AI rounds can go uncounted, so the cap undercounts. The label can also be used up without leaving any visible review.

Proposed rationale: An AI round ending in wait produces no marked review, undercounting paid rounds; fixed in 9a63b50.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/pull/74#discussion_r4235442802) · [source 2](https://github.com/chrystiamjr/git-forge-release-migrator/blob/f38f4a5bfc6efaf32287785b704ebcaa687ab531/scripts/publish-pr-review.mjs)

## case-10: real_bug
PR #73; `scripts/review-pr.mjs`; head `6d54a7416be25481b61b01cd18b8e1bc261230e4`.

<!-- auto-pr-review -->
[important] Replies from every user are sent to the model, and the prompt tells it to drop concerns that replies explain away. On a public repo anyone can reply to a bot comment, so this lets non-owner text past the owner-only gate in a form the model is told to act on. Keep only replies from the PR author or repository owner, and add a test for that filter.

Symbol: `buildPriorReviewComments`

Why: PR content is untrusted prompt input; the owner-only gate exists to limit prompt-injection exposure.

Proposed rationale: Untrusted third-party replies were sent into review context as evidence; fixed in f0ab17a.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/pull/73#discussion_r4235225249) · [source 2](https://github.com/chrystiamjr/git-forge-release-migrator/blob/6d54a7416be25481b61b01cd18b8e1bc261230e4/scripts/review-pr.mjs)

## case-11: clean
PR #74; `scripts/review-pr.mjs`; head `972d972ce111a25e1783c8ffa80fbee0ac28eca3`.

<!-- auto-pr-review -->
[important] Once the cap is reached, the next push runs only the deterministic rules. If those find nothing and checks are green, the verdict is `approve`, and `publish-pr-review.mjs` dismisses the earlier AI `REQUEST_CHANGES` review (`dismissPreviousReviews`). Unresolved critical or important AI findings from the last AI round are therefore silently replaced by a bot approval, and the job passes. Fix: when the gate is closed by the round limit, never upgrade to `approve`. Either emit `wait` or a non-approving COMMENT, or keep `request_changes` while the latest AI round still has blocking findings. Alternatively, skip dismissing earlier AI reviews in that case.

Symbol: `resolveAiReviewGate`

Why: Pushing past the cap turns blocking AI findings into an automatic approval. That silently weakens review gating, which the workflow rules forbid.

Proposed rationale: Post-fix control for the specified concern only, not a claim that the entire PR has no bugs.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/blob/972d972ce111a25e1783c8ffa80fbee0ac28eca3/scripts/review-pr.mjs)

## case-12: clean
PR #74; `scripts/publish-pr-review.mjs`; head `972d972ce111a25e1783c8ffa80fbee0ac28eca3`.

<!-- auto-pr-review -->
[suggestion] `AI_REVIEW_BLOCKING_MARKER` is added whenever the overall verdict is `request_changes` and the LLM completed, even when only a deterministic hard finding (e.g. `missing_pt_br_doc_sync`) blocked and the AI found nothing blocking. After the round limit, `buildPendingAiFinding` then keeps the PR blocked with `llm_review_pending` ('The last AI review round found blocking issues…') after the hard issue is fixed, so the only way out is a paid label round. Fix: have `runReview` record whether the LLM's own findings were blocking (e.g. `llm.blocking = true`) and add the marker only from that flag.

Symbol: `buildReviewBody`

Why: This over-blocks: it wastes a paid AI round and shows a misleading reason, though it fails safe.

Proposed rationale: Post-fix control for the specified concern only, not a claim that the entire PR has no bugs.

Evidence: [source 1](https://github.com/chrystiamjr/git-forge-release-migrator/blob/972d972ce111a25e1783c8ffa80fbee0ac28eca3/scripts/publish-pr-review.mjs)
