# Goal

Create a reusable application layer that powers both the current CLI and the future GUI without changing the public CLI
contract, token precedence rules, artifact outputs, retry semantics, or `summary.json` compatibility.

## Why this sprint exists now

The repository is still structured around CLI-first execution flow. Before any GUI work can safely begin, migration
orchestration needs a typed application boundary that can be reused without duplicating runtime logic. This sprint
creates the service-layer entrypoint, formalizes preflight output, and clarifies ownership between CLI, application,
core, and provider adapters.

## Dependencies and entry criteria

- `AGENTS.md` remains the source of truth for CLI contract, token precedence, artifact requirements, and architectural
  constraints.
- Existing flows in `dart_cli/lib/src/cli.dart`, `dart_cli/lib/src/config.dart`, and `dart_cli/lib/src/migrations/`
  must be understood before orchestration code moves.
- No provider-pair behavior may change during this sprint.
- Existing artifacts under `migration-results/<timestamp>/` must remain mandatory and unchanged.
- Summary schema version `2` and `retry_command` semantics must be preserved.

## Tasks in this sprint

- `task01_extract_application_orchestration.md`
- `task02_preserve_cli_adapter_mapping.md`
- `task03_introduce_structured_preflight.md`
- `task04_tighten_layer_boundaries.md`
