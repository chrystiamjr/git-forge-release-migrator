#!/usr/bin/env bash
set -euo pipefail

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "pre-commit is not installed."
  echo "Install with: pip install pre-commit"
  exit 1
fi

pre-commit install --hook-type pre-commit --hook-type commit-msg --hook-type pre-push

echo "Installed hooks: pre-commit, commit-msg, pre-push"
