---
sidebar_position: 4
title: Artifacts and Sessions
---

Each run writes artifacts under a timestamped work directory:

```text
migration-results/<timestamp>/
```

Required artifacts:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

These files remain the public operational contract for each run. Runtime events can mirror the same execution state for
internal consumers, but operators should still treat these artifacts and `gfrm resume` as the source of truth.

## `summary.json`

Expectations:

- schema version `2`
- executed command metadata
- retry command when failures exist
- artifact paths that match the files written for the run

### Structure and Fields

Each `summary.json` includes:

```json
{
  "schema_version": 2,
  "command": "migrate",
  "order": "GitHub -> GitLab",
  "source": "github.com/owner/repo",
  "target": "gitlab.com/owner/repo",
  "tag_range": {
    "from": "<start>",
    "to": "<end>"
  },
  "dry_run": false,
  "skip_tag_migration": false,
  "skip_release_migration": false,
  "skip_release_asset_migration": false,
  "counts": {
    "tags_created": 10,
    "tags_skipped": 2,
    "tags_failed": 1,
    "tags_would_create": 0,
    "releases_created": 8,
    "releases_updated": 0,
    "releases_skipped": 2,
    "releases_failed": 1,
    "releases_would_create": 0
  },
  "paths": {
    "jsonl_log": "migration-results/2026-04-20T20:30:00Z/migration-log.jsonl",
    "checkpoint": "migration-results/2026-04-20T20:30:00Z/.checkpoint",
    "workdir": "migration-results/2026-04-20T20:30:00Z",
    "failed_tags": "migration-results/2026-04-20T20:30:00Z/failed-tags.txt"
  },
  "failed_tags": ["v2.3.0", "v3.1.0"],
  "retry_command": "gfrm resume",
  "retry_command_shell": "bash"
}
```

**Key fields:**

- `schema_version`: Contract version (always `2`)
- `command`: Whether this was `migrate` or `resume`
- `order` and `source`/`target`: Provider and repository references
- `tag_range`: Semver range for tag filtering (`<start>` and `<end>` represent unbounded)
- `dry_run`: Whether the run was in simulation mode
- **`skip_tag_migration`**: Whether tag migration was skipped (from `--skip-tags`)
- **`skip_release_migration`**: Whether release migration was skipped (from `--skip-releases`)
- **`skip_release_asset_migration`**: Whether release asset migration was skipped (from `--skip-release-assets`)
- `counts`: Breakdown of migration outcomes
  - Tags/releases created, skipped, failed, or would be created (dry-run)
  - Only tags/releases not skipped by flags are included
- `paths`: Locations of all artifacts
- `failed_tags`: Sorted list of tags that failed (empty if all succeeded)
- `retry_command`: Shell command to resume the migration (e.g., `gfrm resume`)
- `retry_command_shell`: Shell hint for the retry command (`bash` or `powershell`)

**Skip flags impact on retry:**

When `skip_*` flags are set, counts reflect items that were actually migrated. When you resume with `gfrm resume`:
- The saved session context preserves skip flags from the initial `migrate` command
- Failed items from the skipped phase are not retried (e.g., if `--skip-releases` was set, only tag failures are in `failed-tags.txt`)
- You can change skip flags on resume to alter what gets retried (e.g., retry releases after fixing a temporary asset issue)

### Triage and Retry

Common fields to inspect during triage:

- `retry_command` to continue the run with `gfrm resume`
- `skip_tag_migration`, `skip_release_migration`, `skip_release_asset_migration` to understand what phases were active
- tag and release counters to see whether the run stopped before or after publication started
- `failed_tags` list and `failed-tags.txt` to identify which items need attention

When the target forge is missing commit history required for pending tags, `summary.json` records the preflight
failure and should be read together with `failed-tags.txt`. The retry command will recheck the commit history before proceeding.

## Runtime events

This runtime also exposes an ordered event stream per run for observability, tests, and future GUI consumers.

- supported sinks in this release: console, JSONL, in-memory, and reducer consumers
- event payloads can mirror status changes and artifact paths such as `summary.json` and `failed-tags.txt`
- runtime events complement observability, but they do not replace `summary.json`, `failed-tags.txt`,
  `migration-log.jsonl`, or `gfrm resume`

## Session files

By default, resumable state is saved under `./sessions/last-session.json` unless a custom `--session-file` is used.

Use `gfrm resume` to continue incomplete work. Do not re-run `migrate` just to recover a partial execution.
If you need to diagnose why a retry cannot proceed yet, inspect the session file alongside `summary.json` and
`migration-log.jsonl`.
