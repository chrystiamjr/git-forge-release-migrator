#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KEEP_TEMP=0
if [[ "${1:-}" == "--keep-temp" ]]; then
  KEEP_TEMP=1
  shift
fi

if [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--keep-temp]" >&2
  exit 2
fi

log_step() {
  echo "==> $1"
}

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

assert_file() {
  local path_value="$1"
  [[ -f "$path_value" ]] || fail "Expected file not found: $path_value"
}

assert_contains() {
  local expected="$1"
  local path_value="$2"
  grep -Fq -- "$expected" "$path_value" || fail "Expected '$expected' in $path_value"
}

assert_not_contains() {
  local expected="$1"
  local path_value="$2"
  if grep -Fq -- "$expected" "$path_value"; then
    fail "Did not expect '$expected' in $path_value"
  fi
}

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gfrm-smoke-XXXXXX")"
cleanup() {
  if [[ "$KEEP_TEMP" -eq 1 ]]; then
    echo "Smoke temp kept at: $SMOKE_ROOT"
    return
  fi

  rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT

DART_RUNNER=()
if command -v fvm >/dev/null 2>&1; then
  DART_RUNNER=(fvm dart)
elif command -v dart >/dev/null 2>&1; then
  DART_RUNNER=(dart)
else
  fail "Neither 'fvm' nor 'dart' is available in PATH."
fi

CLI_CMD=("${DART_RUNNER[@]}" run bin/gfrm_dart.dart)

run_cli() {
  (
    cd "$REPO_ROOT/dart_cli"
    "${CLI_CMD[@]}" "$@"
  )
}

log_step "Repository root: $REPO_ROOT"
log_step "Smoke temp root: $SMOKE_ROOT"
log_step "Ensuring Dart dependencies are available"
(
  cd "$REPO_ROOT/dart_cli"
  "${DART_RUNNER[@]}" pub get >/dev/null
)

log_step "CLI help checks"
run_cli --help >/dev/null
run_cli migrate --help >/dev/null
run_cli resume --help >/dev/null
run_cli demo --help >/dev/null
run_cli settings --help >/dev/null

log_step "Demo dry-run smoke"
DEMO_ROOT="$SMOKE_ROOT/demo-results"
run_cli demo \
  --dry-run \
  --demo-releases 3 \
  --demo-sleep-seconds 0 \
  --quiet \
  --workdir "$DEMO_ROOT" >/dev/null

SUMMARY_FILE="$(find "$DEMO_ROOT" -type f -name 'summary.json' | head -n 1)"
FAILED_TAGS_FILE="$(find "$DEMO_ROOT" -type f -name 'failed-tags.txt' | head -n 1)"
JSONL_FILE="$(find "$DEMO_ROOT" -type f -name 'migration-log.jsonl' | head -n 1)"

[[ -n "$SUMMARY_FILE" ]] || fail "summary.json was not generated in demo run"
[[ -n "$FAILED_TAGS_FILE" ]] || fail "failed-tags.txt was not generated in demo run"
[[ -n "$JSONL_FILE" ]] || fail "migration-log.jsonl was not generated in demo run"

assert_file "$SUMMARY_FILE"
assert_file "$FAILED_TAGS_FILE"
assert_file "$JSONL_FILE"
assert_contains "\"schema_version\": 2" "$SUMMARY_FILE"
assert_contains "\"command\": \"demo\"" "$SUMMARY_FILE"

log_step "Settings flow smoke in isolated project directory"
SETTINGS_PROJECT="$SMOKE_ROOT/settings-project"
mkdir -p "$SETTINGS_PROJECT"

(
  cd "$SETTINGS_PROJECT"
  run_cli setup --yes --local --profile smoke >/dev/null
  run_cli settings set-token-env --provider github --env-name GH_TOKEN --profile smoke --local >/dev/null
  run_cli settings set-token-plain --provider gitlab --token smoke-secret-token --profile smoke --local >/dev/null
  run_cli settings show --profile smoke > "$SMOKE_ROOT/settings-show.json"
)

SETTINGS_FILE="$SETTINGS_PROJECT/.gfrm/settings.yaml"
SHOW_FILE="$SMOKE_ROOT/settings-show.json"
assert_file "$SETTINGS_FILE"
assert_file "$SHOW_FILE"
assert_contains "\"token_plain\": \"***\"" "$SHOW_FILE"
assert_not_contains "smoke-secret-token" "$SHOW_FILE"

log_step "Smoke test passed"
echo "Artifacts checked:"
echo "- Demo summary: $SUMMARY_FILE"
echo "- Demo log: $JSONL_FILE"
echo "- Demo failed tags: $FAILED_TAGS_FILE"
echo "- Settings file: $SETTINGS_FILE"
