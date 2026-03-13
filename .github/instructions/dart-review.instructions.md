---
applyTo: "dart_cli/lib/**/*.dart,dart_cli/test/**/*.dart"
---

# Dart Review Rules

- Treat `AGENTS.md` as the source of truth for CLI contract, invariants, and architecture.
- Preserve the current CLI surface: `migrate`, `resume`, `demo`, `setup`, `settings`.
- Keep token precedence deterministic:
  - `migrate`: settings `token_env`, then `token_plain`, then env aliases
  - `resume`: session token context, then settings `token_env`, then `token_plain`, then env aliases
- Hidden compatibility flags `--source-token` and `--target-token` still exist; do not break them casually.
- Tags-first is mandatory. Releases depend on destination tags unless `--skip-tags` is explicitly used.
- `--skip-tags` is not a shortcut for general migrations. Keep its safety expectations intact.
- Release selection remains semver-only for `vX.Y.Z`. Do not broaden selection unless the repository intentionally changes that policy.
- `summary.json` stays on `schema_version: 2` and failed runs must keep a retry command based on `gfrm resume`.
- Never log raw tokens or expose secret values in errors, output, fixtures, or docs.
- When risky files change, expect focused tests:
  - `config.dart`, `core/settings.dart`, `settings_setup_command_handler.dart` -> config/settings tests
  - `selection.dart`, `engine.dart`, `tag_phase.dart`, `release_phase.dart` -> selection/phase tests
  - `summary.dart`, `cli.dart`, `application/run_service.dart` -> summary/runner tests
- Prefer additive, minimal changes over broad rewrites in migration flow or provider logic.
