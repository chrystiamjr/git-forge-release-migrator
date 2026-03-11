# Task

Bootstrap the Flutter Desktop workspace and shared GUI runtime integration points.

## Intent

Create the desktop application foundation in a way that reuses the existing Dart runtime instead of duplicating
migration logic inside a separate GUI-only codebase.

## Detailed scope

- Add Flutter Desktop project structure for:
  - macOS
  - Windows
  - Linux
- Define where GUI-specific code lives relative to the current Dart CLI package.
- Ensure the GUI can depend on shared runtime contracts introduced in previous sprints.
- Establish a minimal boundary for invoking runtime actions from GUI code without shelling out to CLI commands.
- Prepare the ground for the controller contract later exposed as `DesktopRunController`.

## Expected changes

- The repository contains a Flutter Desktop application scaffold that can build and launch in development mode.
- GUI-specific code is placed in a stable workspace location with clear ownership.
- Shared runtime code remains in the reusable Dart layer rather than being copied into the GUI project.
- The future `DesktopRunController` integration path is technically prepared.

## Non-goals and guardrails

- Do not implement full screens or business flows in this task.
- Do not duplicate provider logic, settings resolution, or migration orchestration inside Flutter-only code.
- Do not shell out to `gfrm` as the default execution strategy.
- Do not change CLI packaging or runtime behavior during workspace bootstrap.

## Test and validation

- Verify the desktop app boots in development mode on supported targets.
- Validate that the GUI workspace can reference shared runtime contracts without code duplication.
- Add basic smoke checks for application startup.
- Keep existing Dart quality gates green with `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart`.

## Exit criteria

- A Flutter Desktop workspace exists in the repository.
- The app can launch on development targets.
- Shared runtime reuse is preserved as the architectural default.
- The repository is ready for shell, navigation, and flow work.
