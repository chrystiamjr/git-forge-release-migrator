# gfrm GUI

Flutter desktop workspace for `gfrm`.

## Scope

This package currently provides the desktop scaffold for:

- macOS
- Windows
- Linux

The GUI reuses shared Dart runtime contracts from `../dart_cli` instead of
shelling out to the CLI binary.

Run Progress renders current controller state and live snapshots, including phase, lifecycle,
tag/release counters, and item outcomes. Wizard start is still disabled; runtime actions go
through `DesktopRunController`. See [runtime events](https://gfrm.envolvosystems.com.br/docs/configuration/runtime-events).

## Quick Start

From the repository root:

```bash
yarn get:flutter
yarn run:flutter:macos
```

Useful commands:

- `yarn lint:flutter`
- `yarn test:flutter`
- `yarn build:flutter:macos`
- `yarn build:flutter:windows`
- `yarn build:flutter:linux`

## Testing

The GUI has two test suites:

**Unit tests** — controllers, mappers, and business logic:
```bash
yarn test:flutter test/unit
```

**Widget flow tests** — simulated flows and user interactions across shell, dashboard, settings, and wizard:
```bash
yarn test:flutter test/e2e
```

Run all tests:
```bash
yarn test:flutter
```

Test structure:
- `test/unit/` — isolated logic without widget rendering
- `test/e2e/` — simulated widget workflows (shell navigation, wizard steps, preflight review)

Ticket validation: see [testing playbook](../docs/engineering/testing-playbook.md). Widget tests do not replace native desktop or live-forge tests.
