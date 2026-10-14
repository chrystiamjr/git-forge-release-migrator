# Source-verifier shadow rollout

Status: prepared for activation after the implementation reaches `main`. **0 of 5 PRs accepted.**
The maintainer authorized this stage on 2026-10-14 after accepting the [pilot results](pilot-results-2026-10-14.json).

## Activation

The automated reviewer checks out the default branch. The implementation on
`feat/review-memory-checklist` therefore needs human review and manual merge before live observation.
Repository variable `AI_REVIEW_VERIFICATION_MODE=shadow` selects the observation mode once that code
is on `main`. Setting it before merge does not activate the old workflow's verifier.

Use the existing `CLAUDE_CODE_OAUTH_TOKEN` repository secret. Keep the current detector routing;
verification uses pinned Claude Code 2.1.296 with Sonnet/medium and the existing bounded read-only
snapshot runner. Effortless remains disabled while its compatibility and routing gates are unresolved.
Shadow mode publishes the baseline review and records verification decisions in the analysis artifact.

## Collect one record per eligible PR

1. Use a real, open, non-draft PR with an owner-authored change and an owner-triggered quality run.
   Normal actor, author, head and review-round gates still apply. Do not change those gates to fill the
   sample. Dependabot-only runs, closed PRs and repeated runs of the same PR are not additional samples.
2. After `Automated PR Review` completes, download its `automated-review-result` artifact before its
   seven-day retention expires. Save the run URL, run attempt, workflow revision, PR number, exact PR
   head/base and artifact SHA-256 alongside the unmodified `auto-pr-review.json` in ignored `.local/`.
3. Confirm the artifact's PR/head matches the selected run and `llm.verification.mode` is `shadow` with
   `status=complete`. Preserve incomplete, skipped and superseded attempts separately; they do not
   count toward five. Never trigger analysis after a PR has closed or merged.
4. Inspect `llm.verification.candidates` and `decisions` together. Record every proposed suppression
   (rejected or inconclusive IDs), including prior assessments and test requirements. Record baseline
   findings, duration, requested settings, `usage`, `model_usage`, and `citation_corrections` when present.
   `llm.duration_seconds` includes detection and verification; verifier duration is separately recorded.
5. Ask the maintainer to adjudicate the suppressions and any missed real bug against that exact head.
   Add the PR to the table only after a complete run and explicit human acceptance. Preserve the
   decision text, timestamp and supporting evidence with the record.

Example artifact download, after selecting a real run ID and a fresh output directory:

```bash
GH_TOKEN="$GH_PERSONAL_TOKEN" gh run download "$REVIEW_RUN_ID" \
  --repo chrystiamjr/git-forge-release-migrator \
  --name automated-review-result --dir "$SHADOW_EVIDENCE_DIR"
```

Store sanitized observation summaries in this document; keep raw artifacts in
`.local/review-shadow/<pr-number>/<head-sha>/<run-id>-<attempt>/`. Link run URLs and record artifact
hashes so later review can distinguish saved evidence from a new run. Missing usage remains unknown;
reported cost alone does not establish routing savings.

| PR | Head / workflow revision | Run / artifact hash | Proposed suppressions | Human decision | Duration / usage |
| --- | --- | --- | --- | --- | --- |

No qualifying live observations have been recorded. Historical benchmark cases do not fill this table.

## Promotion and rollback

Any suppressed real bug stops promotion and requires a corrected candidate plus fresh evidence.
After five distinct PRs have complete evidence and human adjudication, the maintainer decides whether
to enable `enforce`. Neither a passing pilot nor five runs automatically enables it.

For rollback, set repository variable `AI_REVIEW_VERIFICATION_MODE=off`; retain all observations.
Changing the variable affects subsequent job configuration. If an in-flight verifier must also stop,
cancel that workflow run explicitly and preserve its incomplete status.

The pilot suppressed two labeled detector false positives and retained all three detector-found bugs.
Cases 01 and 02 are correlated; case 09 was missed by both stages. Eleven earlier accepted reports
were reused unchanged when case 02 was retried. These limits remain relevant during live observation.
