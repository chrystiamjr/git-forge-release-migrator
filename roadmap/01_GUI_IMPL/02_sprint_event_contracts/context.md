# Goal

Introduce deterministic runtime events and a derived runtime state model that can drive CLI diagnostics, test
observability, and future GUI progress views without scraping terminal output.

## Why this sprint exists now

Once the application boundary exists, the next missing prerequisite for GUI work is observable runtime state. The GUI
cannot safely depend on log parsing or artifact polling. This sprint defines canonical runtime events, stable payload
versioning, ordered delivery, and a reducer-driven `RunState` model that later screens can consume directly.

## Dependencies and entry criteria

- Sprint 1 application service and structured preflight contracts must already exist.
- Existing artifact outputs remain authoritative and must not be replaced in this sprint.
- Event publication must be canonical and provider-agnostic.
- Runtime event schema evolution must be explicit and testable from the start.
- Existing security rules still apply, especially the prohibition on logging raw tokens.

## Tasks in this sprint

- `task01_define_and_version_runtime_events.md`
- `task02_add_serial_publisher_infrastructure.md`
- `task03_build_runstate_reducer.md`
- `task04_preserve_existing_output_contracts.md`
