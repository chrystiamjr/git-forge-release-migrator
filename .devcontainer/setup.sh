#!/usr/bin/env bash
set -euo pipefail

# Dart is pre-installed at /usr/lib/dart by the devcontainer Dockerfile
export PATH="/usr/lib/dart/bin:$HOME/.pub-cache/bin:$PATH"

# Install fvm via pub global (requires Dart on PATH)
dart pub global activate fvm

# Parse Flutter version from .fvmrc (JSON: {"flutter": "3.41.0"})
FLUTTER_VERSION=$(node -e "console.log(require('./.fvmrc').flutter)")

# Install Flutter SDK and set as global via fvm
fvm install "$FLUTTER_VERSION"
fvm global "$FLUTTER_VERSION"

# Persist PATH additions for future shells
echo 'export PATH="$HOME/fvm/default/bin:/usr/lib/dart/bin:$HOME/.pub-cache/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/fvm/default/bin:$PATH"

# Node dependencies (semantic-release, husky, lint tooling)
corepack enable
yarn install

# Dart CLI dependencies
dart pub get --directory dart_cli

# Flutter GUI dependencies
flutter pub get --directory gui

echo ""
echo "✓ gfrm dev environment ready"
echo "  • Flutter $(flutter --version 2>/dev/null | head -1)"
echo "  • Dart $(dart --version 2>/dev/null)"
echo "  • Node $(node --version)"
echo ""
echo "CLI:  cd dart_cli && dart run bin/gfrm_dart.dart --help"
echo "GUI:  cd gui && flutter run -d linux"
