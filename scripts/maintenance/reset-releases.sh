#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Reset GitHub releases/tags and restart from a fresh version tag.

Usage:
  ./scripts/maintenance/reset-releases.sh [options]

Options:
  --new-version <version>  Version tag used with --create-tag/--create-release
  --remote <name>          Git remote to use (default: origin)
  --repo <owner/repo>      Explicit GitHub repository slug (auto-detected by default)
  --create-tag             Create a new tag after cleanup
  --create-release         Create GitHub release after cleanup (implies --create-tag)
  --skip-release           Compatibility flag (forces no release creation)
  --no-backup              Do not create/push backup tag before deletion
  --yes                    Skip interactive confirmation prompt
  --dry-run                Print actions without executing destructive commands
  -h, --help               Show this help

Examples:
  ./scripts/maintenance/reset-releases.sh --yes
  ./scripts/maintenance/reset-releases.sh --create-tag --new-version 0.1.0 --yes
  ./scripts/maintenance/reset-releases.sh --create-release --new-version v0.1.0 --yes
  ./scripts/maintenance/reset-releases.sh --dry-run
EOF
}

require_cmd() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
}

normalize_version_tag() {
  local input="$1"
  local trimmed="${input//[[:space:]]/}"
  if [[ -z "$trimmed" ]]; then
    echo "" && return
  fi

  if [[ "$trimmed" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$trimmed"
    return
  fi

  if [[ "$trimmed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "v$trimmed"
    return
  fi

  echo ""
}

detect_repo_slug_from_remote() {
  local remote_name="$1"
  local remote_url
  remote_url="$(git remote get-url "$remote_name" 2>/dev/null || true)"
  if [[ -z "$remote_url" ]]; then
    echo ""
    return
  fi

  if [[ "$remote_url" =~ ^git@github\.com:([^/]+)/([^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
    return
  fi

  if [[ "$remote_url" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
    return
  fi

  echo ""
}

run_cmd() {
  local dry_run="$1"
  shift

  echo "+ $*"
  if [[ "$dry_run" -eq 1 ]]; then
    return
  fi

  "$@"
}

NEW_VERSION_RAW="v0.1.0"
REMOTE_NAME="origin"
REPO_SLUG=""
CREATE_NEW_TAG=0
CREATE_RELEASE=0
CREATE_BACKUP=1
ASSUME_YES=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --new-version)
      NEW_VERSION_RAW="${2:-}"
      shift 2
      ;;
    --remote)
      REMOTE_NAME="${2:-}"
      shift 2
      ;;
    --repo)
      REPO_SLUG="${2:-}"
      shift 2
      ;;
    --create-tag)
      CREATE_NEW_TAG=1
      shift
      ;;
    --create-release)
      CREATE_RELEASE=1
      CREATE_NEW_TAG=1
      shift
      ;;
    --skip-release)
      CREATE_RELEASE=0
      shift
      ;;
    --no-backup)
      CREATE_BACKUP=0
      shift
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

require_cmd git
require_cmd gh

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Current directory is not a git repository." >&2
  exit 1
fi

if ! git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  echo "Git remote '$REMOTE_NAME' not found." >&2
  exit 1
fi

if [[ "$CREATE_NEW_TAG" -eq 1 ]]; then
  NEW_VERSION_TAG="$(normalize_version_tag "$NEW_VERSION_RAW")"
  if [[ -z "$NEW_VERSION_TAG" ]]; then
    echo "Invalid --new-version '$NEW_VERSION_RAW'. Use semver like 0.1.0 or v0.1.0." >&2
    exit 1
  fi
else
  NEW_VERSION_TAG=""
fi

if [[ -z "$REPO_SLUG" ]]; then
  REPO_SLUG="$(detect_repo_slug_from_remote "$REMOTE_NAME")"
fi

if [[ -z "$REPO_SLUG" ]]; then
  echo "Could not auto-detect GitHub repo slug. Pass --repo <owner/repo>." >&2
  exit 1
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  gh auth status >/dev/null 2>&1 || {
    echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
    exit 1
  }
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo "Repository: $REPO_SLUG"
  echo "Remote: $REMOTE_NAME"
  if [[ "$CREATE_NEW_TAG" -eq 1 ]]; then
    echo "New starting tag: $NEW_VERSION_TAG"
  else
    echo "New starting tag: <skipped>"
  fi
  echo
  echo "This will delete ALL GitHub releases and ALL tags (remote + local)."
  read -r -p "Type 'RESET $REPO_SLUG' to continue: " confirmation
  if [[ "$confirmation" != "RESET $REPO_SLUG" ]]; then
    echo "Cancelled."
    exit 1
  fi
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_TAG="backup/pre-reset-$TIMESTAMP"

if [[ "$CREATE_BACKUP" -eq 1 ]]; then
  run_cmd "$DRY_RUN" git fetch --tags "$REMOTE_NAME"
  run_cmd "$DRY_RUN" git tag "$BACKUP_TAG"
  run_cmd "$DRY_RUN" git push "$REMOTE_NAME" "$BACKUP_TAG"
fi

echo "Collecting release tags from GitHub..."
release_tags="$(gh api --paginate "repos/$REPO_SLUG/releases?per_page=100" --jq '.[].tag_name' 2>/dev/null || true)"
if [[ -n "$release_tags" ]]; then
  while IFS= read -r release_tag; do
    [[ -z "$release_tag" ]] && continue
    run_cmd "$DRY_RUN" gh release delete "$release_tag" --repo "$REPO_SLUG" --yes --cleanup-tag
  done <<<"$release_tags"
fi

echo "Deleting remote tags from '$REMOTE_NAME'..."
remote_tags="$(git ls-remote --tags "$REMOTE_NAME" | awk '{print $2}' | sed 's#refs/tags/##' | sed 's/\^{}//' | sort -u)"
if [[ -n "$remote_tags" ]]; then
  while IFS= read -r remote_tag; do
    [[ -z "$remote_tag" ]] && continue
    if [[ "$remote_tag" == "$BACKUP_TAG" ]]; then
      continue
    fi
    run_cmd "$DRY_RUN" git push "$REMOTE_NAME" ":refs/tags/$remote_tag"
  done <<<"$remote_tags"
fi

echo "Deleting local tags..."
local_tags="$(git tag -l)"
if [[ -n "$local_tags" ]]; then
  while IFS= read -r local_tag; do
    [[ -z "$local_tag" ]] && continue
    if [[ "$local_tag" == "$BACKUP_TAG" ]]; then
      continue
    fi
    run_cmd "$DRY_RUN" git tag -d "$local_tag"
  done <<<"$local_tags"
fi

if [[ "$CREATE_NEW_TAG" -eq 1 ]]; then
  run_cmd "$DRY_RUN" git tag -a "$NEW_VERSION_TAG" -m "Initial release $NEW_VERSION_TAG"
  run_cmd "$DRY_RUN" git push "$REMOTE_NAME" "$NEW_VERSION_TAG"
fi

if [[ "$CREATE_RELEASE" -eq 1 && "$CREATE_NEW_TAG" -eq 1 ]]; then
  run_cmd "$DRY_RUN" gh release create "$NEW_VERSION_TAG" --repo "$REPO_SLUG" --title "$NEW_VERSION_TAG" --generate-notes
fi

echo
echo "Done."
echo "Validation commands:"
echo "  gh release list --repo $REPO_SLUG"
echo "  git ls-remote --tags $REMOTE_NAME"
if [[ "$CREATE_NEW_TAG" -eq 0 ]]; then
  echo "No new tag/release created. CI can create the next version tag/release."
fi
