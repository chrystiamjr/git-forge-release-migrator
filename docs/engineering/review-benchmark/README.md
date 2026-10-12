# Headless review experiment

The verifier and experiment harness are implemented with production verification **off by default**.
No benchmark success or live rollout is claimed. The initial Effortless compatibility check failed;
see [compatibility.json](compatibility.json). No global plugin installation was made.
The maintainer accepted all 12 proposed labels on 2026-10-12; their confirmations are recorded in the corpus.

## 1. Confirm labels

Review [labels.md](labels.md), about 15–20 minutes. Set each `confirmed_label` and the top-level
`confirmed_by` in [cases.json](cases.json) only after the maintainer confirms the labels. Six proposed
false positives include an accepted-policy disagreement; two concern the same adapter. Two clean
controls cover named fixed concerns, not whole-PR cleanliness. This is a correlated pilot dataset.

Historical heads are from review comments' **original** commit IDs, not their moving commit IDs.
Bases are fixed merge bases. Later replies, claims and proposed labels are adjudication-only and
never enter prompts. Historical PR descriptions are unavailable, so the harness uses a neutral title
and immutable code. Current trusted review instructions are held constant across arms.

## 2. Check prerequisites

```bash
node scripts/review-benchmark.mjs check
```

Use Claude Code `2.1.296`, Node from `.nvmrc`, Python 3 and `gh`. Configure `GH_TOKEN` using the repository
account rule for read-only source retrieval. Configure `CLAUDE_CODE_OAUTH_TOKEN` through your secret
environment, never in a file or command argument. API billing credentials and Jev are excluded from
isolated model processes. Existing interactive login alone is not copied into the temporary home.

The pinned Effortless `1.71.0` revision fails `claude plugin validate`: `effortless.updateCheck` is
undeclared. Its adapter validates before loading hooks. A different revision requires a deliberate
pin update, source review and new compatibility result; no fallback to an unpinned latest version.
`--restricted` confines model file tools; it is not an OS sandbox for trusted plugin code.

## 3. Run and adjudicate one case at a time

```bash
node scripts/review-benchmark.mjs run --case case-01 --arm current --out /tmp/gfrm-review-benchmark
```

Repeat for cases 01–12. Each source comparison refuses a truncated GitHub file list. Baseline detector
outputs are cached by immutable head and prompt fingerprint and reused for verification. Each report
contains detector and filtered findings, exact versions, usage, durations and incomplete results.
Reports are exclusive-create: choose a fresh output directory for a repeat rather than overwrite evidence.

When plugin compatibility is resolved, compare `--arm effortless-effort` and `--arm effortless-model`
using the same corpus and output directory. Effort-only holds the baseline's model constant; model
routing starts at Opus and may move down. The original Haiku router is not layered onto a plugin call.
The same bounded PR summary precedes each detector prompt. The verifier remains Sonnet/medium.
The detector has no tools; only verification receives read-only snapshot tools.

Human adjudication maps each report's findings to the case's labeled concern. Set its
`adjudication.confirmed_by`, `baseline_detected`, `candidate_detected` and supporting finding IDs.
Inspect other findings too: the 12 concern labels cannot exhaustively measure every possible bug.

```bash
node scripts/review-benchmark.mjs score --arm current --out /tmp/gfrm-review-benchmark
```

The preliminary quality gate needs at least 50% suppression of baseline false positives, no lost
baseline real bugs and no new false positives on clean controls. Missing/incomplete or unadjudicated
trials stay pending. An Effortless report's main-loop usage must not be presented as total usage:
upstream proof logs omit judge token usage. Routing savings remain unproven until complete accounting
or a separately reviewed paired latency comparison is available. Repeat marginal differences.

## 4. Observe five real PRs

Only after the verifier quality gate passes, set `AI_REVIEW_VERIFICATION_MODE=shadow` in the repository.
Record five **distinct PRs**, their exact heads, run URLs, baseline findings, suppressed candidate IDs,
verification status, human adjudication and duration/usage in a rollout report. Incomplete runs do not
count toward five. The artifact contains verification decisions even though publication stays baseline.

Review every proposed suppression. Any lost real bug stops promotion and requires a corrected candidate
and fresh evidence. The maintainer explicitly decides whether evidence supports `enforce`. Neither
the benchmark command nor the workflow changes repository variables automatically. Set the mode back
to `off` for rollback. Effortless stays experiment-only while its compatibility or routing gate fails.

## References

- [Pinned plugin source](https://github.com/HeyCubit/effortless/tree/e553b18e9f5e8ce3533f3ce9c666e7e8bc9234f9)
- [Upstream headless benchmark](https://github.com/HeyCubit/effortless/blob/e553b18e9f5e8ce3533f3ce9c666e7e8bc9234f9/bench/agentic/run.sh)
- [Claude Code mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
