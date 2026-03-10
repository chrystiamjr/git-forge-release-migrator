#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

if ! command -v yarn >/dev/null 2>&1; then
  echo "Error: yarn is required to install Husky hooks. Install Yarn and run this script again."
  exit 1
fi

echo "Installing dependencies with yarn install (required for Husky setup)..."
yarn install
yarn prepare

echo "Installed Husky hooks: pre-commit, pre-push"
