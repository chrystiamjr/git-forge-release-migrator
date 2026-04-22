---
sidebar_position: 6
title: smoke
---

Run a real end-to-end smoke test against throwaway test repositories on two forges. Dispatches fixture CI workflows to seed fake releases on the source, migrates them to the target, validates artifacts, and tears down the source.

See also: [Smoke testing guide](../guides/smoke-testing.md).

## Syntax

```bash
gfrm smoke \
  --source-provider <github|gitlab|bitbucket> \
  --source-url <repo-url> \
  --target-provider <github|gitlab|bitbucket> \
  --target-url <repo-url> \
  [options]
```

## Typical use

```bash
gfrm smoke \
  --source-provider github --source-url https://github.com/you/gfrm-test-source \
  --target-provider gitlab --target-url https://gitlab.com/you/gfrm-test-target
```

## What it does

1. Dispatches the `create-fake-releases` workflow on the source. Waits for completion.
2. Cooldown (default 15s) to avoid forge abuse heuristics.
3. Runs `gfrm migrate` from source to target.
4. Validates artifact contract (`summary.json`, `failed-tags.txt`, `migration-log.jsonl`).
5. Cooldown.
6. Dispatches the `cleanup-tags-and-releases` workflow on the source.

## Prerequisites

Before running `gfrm smoke`:

- Two throwaway test repositories, one per forge, following the [smoke testing guide](../guides/smoke-testing.md).
- Fixture CI workflows installed in each test repository (copied from `docs/smoke-tests/workflows/<forge>/`).
- Personal tokens exposed via `settings.yaml` (see `gfrm setup`) or the standard provider env aliases.

## Options

### Required

| Flag | Description |
|---|---|
| `--source-provider` | `github`, `gitlab`, or `bitbucket` |
| `--source-url` | Full URL of the source test repository |
| `--target-provider` | `github`, `gitlab`, or `bitbucket` |
| `--target-url` | Full URL of the target test repository |

### Orchestration

| Flag | Default | Description |
|---|---|---|
| `--mode` | `happy-path` | Execution mode: `happy-path`, `contract-check`, `partial-failure-resume` |
| `--skip-setup` | off | Skip the fixture create step. Use when the source is already populated |
| `--skip-teardown` | off | Skip the cleanup step. Leaves the source populated for inspection |
| `--cooldown-seconds` | `15` | Seconds to sleep between phases |
| `--poll-interval` | `10` | Seconds between CI status polls |
| `--poll-timeout` | `300` | Seconds to wait for a CI workflow before failing |

### Migration options

| Flag | Description |
|---|---|
| `--settings-profile` | Profile name in `settings.yaml` |
| `--workdir` | Root directory for smoke artifacts |
| `--quiet` | Suppress interactive output |
| `--json` | Emit JSON logs |

`gfrm smoke` accepts the options listed on this page. It does not forward arbitrary `gfrm migrate` flags to the migration phase.

Token precedence matches `gfrm migrate`: settings (`token_env`, then `token_plain`) first, then provider env aliases such as `GITHUB_TOKEN`, `GH_TOKEN`, `GITLAB_TOKEN`, and `BITBUCKET_TOKEN`. `--settings-profile` selects the settings profile used for both source and target token lookup.

## Modes

| Mode | Behavior |
|---|---|
| `happy-path` | Full flow. Expects no partial failure |
| `contract-check` | happy-path + assert `summary.retry_command` is empty |
| `partial-failure-resume` | happy-path + follow `summary.retry_command` or run a synthetic `gfrm resume` against the first source tag |

## Examples

### GitHub → GitLab (default mode)

```bash
gfrm smoke \
  --source-provider github --source-url https://github.com/you/gfrm-test-source \
  --target-provider gitlab --target-url https://gitlab.com/you/gfrm-test-target
```

### Keep source populated for debugging

```bash
gfrm smoke \
  --source-provider github --source-url https://github.com/you/gfrm-test-source \
  --target-provider gitlab --target-url https://gitlab.com/you/gfrm-test-target \
  --skip-teardown
```

### Against pre-seeded source

```bash
gfrm smoke \
  --skip-setup \
  --source-provider gitlab --source-url https://gitlab.com/you/gfrm-test-source \
  --target-provider github --target-url https://github.com/you/gfrm-test-target
```

### Contract check mode in CI

```bash
gfrm smoke \
  --mode contract-check \
  --cooldown-seconds 0 \
  --source-provider bitbucket --source-url https://bitbucket.org/you/gfrm-test-source \
  --target-provider github --target-url https://github.com/you/gfrm-test-target
```

## Exit codes

- `0` — full round-trip succeeded, artifacts valid
- `1` — any phase failed (fixture dispatch, migration, validation, or teardown). See `migration-log.jsonl` and `summary.json` in the workdir
- `2` — invalid CLI arguments

## Troubleshooting

- **403 from a forge** — your test project may be rate-limited. Wait 24h or rotate to a fresh test repository. See the [smoke testing guide](../guides/smoke-testing.md#troubleshooting).
- **CI workflow not triggered** — check that the workflow file is on the default branch and `workflow_dispatch`/`custom` trigger is enabled.
- **Cleanup failed** — run `gfrm smoke --skip-setup --skip-teardown` then manually trigger the cleanup workflow in the forge UI.
