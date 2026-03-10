# GitHub Copilot Instructions

Use [AGENTS.md](../AGENTS.md) as the primary project context before proposing or generating code.

Required behavior:

- Read and follow architecture, invariants, and business rules from `AGENTS.md`.
- Preserve existing behavior for unaffected provider pairs.
- Keep documentation in sync when changing supported pairs, auth model, or output contracts.
- Prefer minimal, safe, additive changes over broad rewrites in migration flows.
- Run and pass Dart quality gates after relevant code changes:
  - `yarn lint:dart`
  - `yarn test:dart`

If any instruction here conflicts with `AGENTS.md`, treat `AGENTS.md` as source of truth for repository-specific behavior.
