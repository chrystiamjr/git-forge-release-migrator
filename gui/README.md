# gfrm GUI

Flutter desktop workspace for `gfrm`.

## Scope

This package currently provides the desktop scaffold for:

- macOS
- Windows
- Linux

The GUI reuses shared Dart runtime contracts from `../dart_cli` instead of
shelling out to the CLI binary.

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
yarn test:flutter -- --path=test/unit
```

**E2E integration tests** — visual flows and user interactions across shell, dashboard, settings, and wizard:
```bash
yarn test:flutter -- --path=test/e2e
```

Run all tests:
```bash
yarn test:flutter
```

Test structure:
- `test/unit/` — isolated logic without widget rendering
- `test/e2e/` — orchestrated workflows (shell navigation, wizard steps, preflight review)
