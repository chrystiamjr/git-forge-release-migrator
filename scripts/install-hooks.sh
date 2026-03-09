#!/usr/bin/env bash
set -euo pipefail

yarn install
yarn prepare

echo "Installed Husky hooks: pre-commit, pre-push"
