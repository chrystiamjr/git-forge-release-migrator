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
