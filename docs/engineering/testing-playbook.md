# Project testing playbook

## Environment and baseline

Use pinned `.fvmrc` Flutter and `.nvmrc` Node versions. From repository root, install locked Yarn dependencies; resolve Dart and Flutter packages in their own directories:

```bash
yarn install --immutable
cd dart_cli
fvm dart pub get
cd ../gui
fvm flutter pub get
cd ..
```

Capture baseline on the fixed PR-base revision in an explicitly authorized separate worktree (do not silently stash/checkout existing work):

```bash
yarn verify:ticket --baseline-only --out /tmp/gfrm-baseline
```

The baseline command measures Dart and GUI coverage. Preserve its `validation-report.json`; it must identify the requested base SHA, matching production scope and successful measurements. Baselines exclude generated `.g.dart` files. Never substitute an old snapshot or report missing coverage as 0%/passed.

## Final verification

After committing the selected changes, run:

```bash
yarn verify:ticket --ticket GFRM-23 --base <fixed-base-sha> --baseline-report <baseline-report.json> --out /tmp/gfrm-validation
```

Use the actual ticket ID; standalone process work may use a `LOCAL-<slug>` ID with no tracker mutation. The command refuses dirty source because its report identifies immutable tested source. Before commit, use the focused commands below; Git hooks still run. Validation failure may leave a local commit, but must prevent successful delivery/merge readiness. No push is implied by verification.

The runner invokes existing checks, captures redacted logs and writes versioned JSON/Markdown evidence keyed by commit. It exits nonzero for failures or required pending evidence, and does not update tickets or PRs.

| Scope | Checks |
| --- | --- |
| Every implementation | `yarn lint:dart`, `yarn test:dart`, `yarn coverage:dart`, diff whitespace and offline secret patterns |
| GUI/shared runtime | `yarn lint:flutter`, `yarn coverage:flutter` (unit/widget suite plus coverage) |
| Visible GUI | Maintained golden comparison (`yarn test:flutter:visual`); overflow/scroll tests; human inspection of diffs |
| Website/public docs | Translation parity and `yarn docs:build` EN/PT-BR; `yarn test:website` for React changes |
| Process/tooling | `yarn test:process`; mocked API and event behavior |
| Platform runners | Required matching native acceptance evidence |
| Provider adapters | Required matching live-forge acceptance evidence, separate from fake integration |

Dart and GUI floors are 80%; changed production scopes cannot regress against comparable base coverage. An absent required baseline is pending. Exceptions require an explicit reviewed policy change, never silent threshold lowering. Coverage collection executes tests; CI need not repeat them unnecessarily.

## Acceptance scenarios

- Runtime/provider: six supported cross-forge directions; tags before semver releases; safe `--skip-tags`; terminal checkpoints skip completed work and retry incomplete work; assets plus Bitbucket manifest behavior; missing source manifest alone is nonfatal.
- CLI/auth: deterministic migrate/resume token precedence; expected exit codes; no raw token in console/JSONL/summary; `summary.json` schema 2; required artifacts and `gfrm resume` retry command.
- GUI: current snapshot before stream updates, ordered counters/phases, late entry/re-entry, terminal state/failure, stream errors, disposal and new-run reset. Widget-flow tests use `test/e2e`; they are simulated, not native E2E.
- CLI/packaging: compile changed executables; run `--help` and credential-free `demo` in an isolated workdir; verify artifacts and failures before real smoke.
- UI: deterministic state fixtures, bundled fonts, fixed clocks/theme/window sizes (1280x800 and another supported size). Golden updates require human visual review; never use `--update-goldens` in validation CI. Ensure full-window captures and scrollability, not an accidentally cropped baseline.
- Native: build/launch and interact on the affected OS; missing OS/hardware is pending when acceptance requires it. Wizard start remains unavailable until its own ticket implements it.
- Live: follow [smoke testing guide](../../website/docs/guides/smoke-testing.md) with authorized allowlisted throwaway repos. Verify fixtures, migration/retry, artifacts and cleanup. Credentials/test repositories are prerequisites; never touch production by inference.

Focused subsets:

```bash
cd gui
fvm flutter test test/unit
fvm flutter test test/e2e
```

## External evidence and review

For required native/live acceptance, supply `--evidence-dir <directory>` with `native.json`/`live.json`:

```json
{
  "ticket": "GFRM-23",
  "head_sha": "<full-tested-head-sha>",
  "kind": "native",
  "status": "passed",
  "artifacts": [{"path": "<actual-proof-file>", "sha256": "<sha256>"}]
}
```

This verifies identity and artifact presence/hashes, not the truth of a human scenario: reviewers inspect the scenario description and results. Do not upload tokens or sensitive session files. Secret patterns supplement behavioral tests, not a security audit. Retain sanitized reports, LCOV and applicable screenshots/diffs with the CI run; temporary local capture scripts are not permanent regression tests.

Finish with focused code review and an acceptance-to-evidence checklist. Any missing required scenario stays pending. Deliver to Review with both links; [ticket delivery](ticket-delivery.md) owns completion semantics.

## Canonical visual CI and baseline approval

`yarn test:flutter` and `yarn coverage:flutter` exclude the `visual` tag. `yarn test:flutter:visual` compares maintained progress-content goldens with bundled fonts at 1280x800 and 1024x768. Core widget-flow tests still verify shell navigation and stream binding. These goldens render page content, not native window chrome or a live forge migration.

The canonical visual job uses `macos-14` and the pinned Flutter SDK; fixture theme is fixed to remove host platform differences. Initial PNGs in a PR are **proposed baselines** requiring human inspection. Validation never updates them automatically. Core Linux CI records visual work, and required native/live acceptance, as delegated; `passed_core` is not a final delivery result. The required `ticket-validation` job only succeeds after both core and canonical visual jobs succeed. A failed, cancelled or skipped required job does not become a successful ticket gate.

`prepare-validation-baseline.mjs` creates an isolated fixed-base worktree in CI, resolves dependencies and measures matching production coverage. Local source must be committed; test SDK environment sanitization applies only to subprocesses. CI reports preserve tested revision/base, sanitized logs and LCOV. Native/live artifacts remain distinct acceptance evidence: CI cannot produce them, so `--ci-core` delegates them, and local `yarn verify:ticket` keeps any missing required scenario pending.

Golden baselines must come from the pinned canonical macOS 14 CI runner, not an arbitrary local OS. Different macOS font rasterizers can produce genuine pixel differences even with the same Flutter version and bundled font bytes. Keep exact comparison; inspect CI `testImage`, `masterImage` and diff diagnostics, propose reviewed baseline changes, then require a clean canonical comparison run. Local noncanonical visual comparisons may remain pending; do not claim a full local aggregate pass when they differ. Core/widget checks and canonical CI evidence remain separate. Never regenerate baselines automatically during normal CI.
