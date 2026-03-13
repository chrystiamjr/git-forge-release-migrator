# GitHub Copilot Instructions

Use [AGENTS.md](../AGENTS.md) as the primary repository context before reviewing or generating code.

For pull request review on GitHub:

- Read the changed files broadly before commenting. Prefer breadth first, then depth on risky areas.
- Comment only on concrete problems, regressions, security issues, or contract drift. Do not add praise or generic summary comments.
- Keep comments inline, specific, and actionable.
- Treat these repository invariants as high priority:
  - tags migrate before releases
  - `--skip-tags` stays a constrained option, not a general shortcut
  - release selection remains semver-only for `vX.Y.Z`
  - token precedence remains deterministic and documented
  - `summary.json` stays on schema version `2`
  - failed runs keep retry guidance based on `gfrm resume`
  - raw tokens must never be logged
- When public behavior changes, keep docs in sync across:
  - `website/docs/**`
  - `website/i18n/pt-BR/docusaurus-plugin-content-docs/current/**`
  - `README.md`
  - `dart_cli/README.md` when runtime or developer workflow changes
- Prefer minimal, safe, additive changes over broad rewrites in migration flow, provider adapters, or CLI contract code.
- After relevant code changes, expect the repository quality gates to pass:
  - `yarn lint:dart`
  - `yarn test:dart`
  - `yarn coverage:dart` for production behavior changes

If any instruction here conflicts with `AGENTS.md`, treat `AGENTS.md` as the source of truth.
