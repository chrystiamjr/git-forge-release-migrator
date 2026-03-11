# Goal

Ship the first desktop GUI foundation for Windows, macOS, and Linux using Flutter, while reusing the shared Dart
runtime contracts from Sprints 1 and 2 instead of creating a parallel execution path.

## Why this sprint exists now

The GUI should only begin after orchestration and observability contracts are stable. With a typed application service
and event-driven runtime state in place, this sprint can focus on desktop shell construction, MVP screens, and the
shared runtime boundary without re-litigating migration semantics.

## Dependencies and entry criteria

- Sprint 1 application service and Sprint 2 event contracts must exist and be stable enough for GUI consumption.
- Flutter Desktop is the chosen implementation technology for Windows, macOS, and Linux.
- The CLI remains first-class and continues to define migration behavior.
- The approved visual direction must exist before design-system work begins.
- GUI runtime actions must call shared typed services rather than shelling out to `gfrm`.

## Tasks in this sprint

- `task01_bootstrap_flutter_desktop_workspace.md`
- `task02_implement_desktop_shell_and_navigation.md`
- `task03_wire_wizard_to_runtime_contracts.md`
- `task04_render_live_progress_from_runstate.md`
- `task05_add_retry_and_diagnostics_actions.md`
