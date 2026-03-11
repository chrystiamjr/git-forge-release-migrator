# Task

Implement the desktop shell, route structure, and primary navigation model.

## Intent

Provide the application frame that hosts the MVP screens and allows users to move between dashboard, wizard, run
progress, results, and history without coupling navigation to runtime internals.

## Detailed scope

- Build the desktop application shell using the approved visual direction.
- Define navigation and route structure for:
  - Dashboard
  - New Migration
  - Run Progress
  - Migration Results
  - History
- Introduce reusable navigation primitives that fit the future design system.
- Ensure the shell behaves sensibly on common desktop window sizes and does not assume full-screen layout.
- Ensure history and results navigation remain accessible even when no run is currently active.

## Expected changes

- The GUI has a stable application frame and route map for the MVP screens.
- Navigation is explicit and reusable rather than embedded in individual screen implementations.
- Shared shell primitives can be reused by later design-system work.
- Users can reach the core GUI surfaces without runtime-specific hacks or implicit screen transitions.

## Non-goals and guardrails

- Do not complete runtime wiring in this task.
- Do not make navigation depend on parsing terminal output or filesystem side effects.
- Do not collapse all screens into one oversized widget or route handler.
- Do not assume mobile layouts or browser-only patterns for a desktop-first experience.

## Test and validation

- Add widget or UI tests for route transitions between the five MVP screens.
- Validate startup behavior when there is:
  - no active run
  - an active run in progress
  - historical runs available
- Add smoke checks for window-size resilience on common desktop layouts.
- Keep existing runtime tests passing unchanged.

## Exit criteria

- The GUI has a desktop shell and navigation model covering all MVP screens.
- Navigation is independent from runtime implementation details.
- The application frame is ready for wizard, progress, and results wiring.
- Core GUI movement works in controlled scenarios.
