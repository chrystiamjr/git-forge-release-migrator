# CLI Reference (English)

## Canonical Command

```bash
./bin/repo-migrator.py \
  --source-provider <github|gitlab|bitbucket> \
  --source-url <url> \
  --source-token <token> \
  --target-provider <github|gitlab|bitbucket> \
  --target-url <url> \
  --target-token <token>
```

## Full Option Reference

- `--source-provider <github|gitlab|bitbucket>`
- `--source-url <url>`
- `--source-token <token>`
- `--target-provider <github|gitlab|bitbucket>`
- `--target-url <url>`
- `--target-token <token>`
- `--skip-tags`
- `--from-tag <tag>`
- `--to-tag <tag>`
- `--workdir <dir>` (default: `./migration-results`)
- `--log-file <path>`
- `--dry-run`
- `--download-workers <n>` (default: `4`, max: `16`)
- `--release-workers <n>` (default: `1`, max: `8`)
- `--checkpoint-file <path>` (default: `<results-root>/checkpoints/state.jsonl`)
- `--tags-file <path>` (one tag per line)
- `--non-interactive`
- `--no-banner`
- `--quiet`
- `--json`
- `--progress-bar`
- `--help`
- `--load-session`
- `--save-session` (enabled by default)
- `--no-save-session`
- `--resume-session`
- `--session-file <path>`
- `--session-token-mode <env|plain>` (default: `env`)
- `--session-source-token-env <env_name>` (default: `GFRM_SOURCE_TOKEN`)
- `--session-target-token-env <env_name>` (default: `GFRM_TARGET_TOKEN`)
- `--demo-mode`
- `--demo-releases <n>`
- `--demo-sleep-seconds <seconds>`

## Session Persistence

Defaults:

- session file: `./sessions/last-session.json`
- token mode: `env`

Commands:

```bash
./bin/repo-migrator.py --resume-session
./bin/repo-migrator.py --load-session --session-file ./sessions/custom.json
./bin/repo-migrator.py --no-save-session
```

Warning: `--session-token-mode plain` stores tokens in plaintext.

## Output Artifacts

Each run creates:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Main files:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

When failures exist, `summary.json` includes a retry command for only failed tags.

## Exit Codes

- `0`: migration completed without failures
- `1`: at least one failure occurred

## Provider Notes

- Supported now: `gitlab -> github`, `github -> gitlab`
- Any pair with `bitbucket` returns explicit not-implemented error

## GitHub Auth Behavior

For GitHub operations, commands are executed with runtime token override:

```bash
GH_TOKEN="<target_token>" gh ...
```
