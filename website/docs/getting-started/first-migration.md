---
sidebar_position: 3
title: First Migration
---

This is the shortest useful migration path.

## Configure tokens once

```bash
./gfrm setup
```

Use [Settings Profiles](/configuration/settings-profiles) if you need more than one environment.

## Run a real migration

```bash
./gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo"
```

## Validate without writing to the target

```bash
./gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --dry-run
```

## Inspect artifacts

Every run writes under:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Expected artifacts:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

If failures exist, `summary.json` includes a `retry_command` that uses `gfrm resume`.
