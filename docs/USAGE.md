# CLI Reference (English)

## Canonical Command

```bash
./bin/repo-migrator.py \
  --source-provider <github|gitlab|bitbucket> \
  --source-url <url> \
  [--source-token <token>] \
  --target-provider <github|gitlab|bitbucket> \
  --target-url <url> \
  [--target-token <token>] \
  [--settings-profile <name>]
```

## Supported Pairs

Cross-forge pairs currently supported:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> github` (Bitbucket Cloud)
- `gitlab -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> gitlab` (Bitbucket Cloud)

Not supported in this phase:

- same-provider pairs (`github->github`, `gitlab->gitlab`, `bitbucket->bitbucket`)
- Bitbucket Data Center / Server hosts

## Command Recipes

```bash
# GitLab -> GitHub
./bin/repo-migrator.py --non-interactive \
  --source-provider gitlab --source-url "https://gitlab.com/group/project" --source-token "<gitlab_token>" \
  --target-provider github --target-url "https://github.com/org/repo" --target-token "<github_token>"

# GitHub -> GitLab
./bin/repo-migrator.py --non-interactive \
  --source-provider github --source-url "https://github.com/org/repo" --source-token "<github_token>" \
  --target-provider gitlab --target-url "https://gitlab.com/group/project" --target-token "<gitlab_token>"

# GitHub -> Bitbucket Cloud
./bin/repo-migrator.py --non-interactive \
  --source-provider github --source-url "https://github.com/org/repo" --source-token "<github_token>" \
  --target-provider bitbucket --target-url "https://bitbucket.org/workspace/repo" --target-token "<bitbucket_bearer>"

# Bitbucket Cloud -> GitLab
./bin/repo-migrator.py --non-interactive \
  --source-provider bitbucket --source-url "https://bitbucket.org/workspace/repo" --source-token "<bitbucket_bearer>" \
  --target-provider gitlab --target-url "https://gitlab.com/group/project" --target-token "<gitlab_token>"

# Dry-run with explicit tag range
./bin/repo-migrator.py --non-interactive --dry-run \
  --source-provider gitlab --source-url "https://gitlab.com/group/project" --source-token "<gitlab_token>" \
  --target-provider bitbucket --target-url "https://bitbucket.org/workspace/repo" --target-token "<bitbucket_bearer>" \
  --from-tag v1.0.0 --to-tag v2.0.0
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
- `--settings-profile <name>`
- `--demo-mode`
- `--demo-releases <n>`
- `--demo-sleep-seconds <seconds>`

## Settings Subcommands

```bash
./bin/repo-migrator.py settings init [--profile <name>] [--local] [--yes]
./bin/repo-migrator.py settings set-token-env --provider <github|gitlab|bitbucket> --env-name <ENV_NAME> [--profile <name>] [--local]
./bin/repo-migrator.py settings set-token-plain --provider <github|gitlab|bitbucket> [--token <value>] [--profile <name>] [--local]
./bin/repo-migrator.py settings unset-token --provider <github|gitlab|bitbucket> [--profile <name>] [--local]
./bin/repo-migrator.py settings show [--profile <name>]
```

### Settings Paths and Merge Strategy

- global: `~/.config/gfrm/settings.yaml`
- local override: `./.gfrm/settings.yaml`

Merge behavior:

1. read global settings
2. read local settings
3. deep-merge local over global

Local settings only override matching keys and preserve the rest of global configuration.

### Profile Selection and Switching

Effective profile order:

1. `--settings-profile`
2. `defaults.profile` in merged settings
3. `default`

Switch profiles at runtime:

```bash
./bin/repo-migrator.py --settings-profile work ...
./bin/repo-migrator.py --settings-profile personal ...
```

Set per-profile credentials:

```bash
./bin/repo-migrator.py settings set-token-env --provider github --env-name GH_WORK_TOKEN --profile work
./bin/repo-migrator.py settings set-token-env --provider github --env-name GH_PERSONAL_TOKEN --profile personal
```

If you omit `--profile` in settings commands, the same effective profile resolution is used.

### YAML Schema (v1)

```yaml
version: 1
defaults:
  profile: work
profiles:
  work:
    providers:
      github:
        token_env: GH_WORK_TOKEN
      gitlab:
        token_env: GL_WORK_TOKEN
  personal:
    providers:
      github:
        token_env: GH_PERSONAL_TOKEN
      bitbucket:
        token_plain: bbp_example_plain_token
```

Provider credential fields:

- `token_env`: preferred, resolved via environment variable name
- `token_plain`: explicit plaintext token

`settings show` masks `token_plain`.

`settings init` performs a read-only scan of `~/.zshrc`, `~/.zprofile`, `~/.bashrc`, and `~/.bash_profile` to suggest env names. It never edits those files.
`settings init` does not set `token_plain`; use `settings set-token-plain` when needed.

## Token Resolution Order

For each side (`source` and `target`), resolution order is:

1. explicit CLI arg token (`--source-token` / `--target-token`)
2. loaded session token values (`--load-session` / `--resume-session`)
3. settings profile provider config:
   - `token_env` (resolved via environment)
   - `token_plain` (optional explicit plaintext value)
4. environment aliases:
   - `GFRM_SOURCE_TOKEN` / `GFRM_TARGET_TOKEN`
   - GitHub: `GITHUB_TOKEN`, `GH_TOKEN`, `GH_PERSONAL_TOKEN`
   - GitLab: `GITLAB_TOKEN`, `GL_TOKEN`
   - Bitbucket: `BITBUCKET_TOKEN`, `BB_TOKEN`
5. interactive prompt (when interactive mode is enabled)

## Tag Selection and Ordering

- The migration engine currently selects tags matching `vX.Y.Z`.
- Selection order is ascending semantic version.
- `--from-tag` and `--to-tag` are inclusive.
- `--tags-file` acts as an additional filter after provider discovery.

## Provider Behavior Notes

- GitHub auth is performed with runtime token override:

```bash
GH_TOKEN="<token>" gh ...
```

- GitLab auth uses `PRIVATE-TOKEN` header.
- Bitbucket auth in this phase uses:

```text
Authorization: Bearer <token>
```

- Bitbucket URL scope in this phase is limited to:

```text
https://bitbucket.org/<workspace>/<repo>
```

## Bitbucket Manifest Model

Bitbucket release state is tracked in Downloads via:

```text
.gfrm-release-<tag>.json
```

Manifest role:

- allows idempotent retries for `-> bitbucket` flows
- marks whether assets are complete or pending
- carries normalized release metadata used by `bitbucket -> *` flows

Typical payload shape:

```json
{
  "version": 1,
  "tag_name": "v1.2.3",
  "release_name": "Release v1.2.3",
  "notes_hash": "<sha256>",
  "uploaded_assets": [
    {"name": "app.zip", "url": "https://...", "type": "package"}
  ],
  "missing_assets": [],
  "updated_at": "2026-01-01T00:00:00Z"
}
```

Legacy behavior (no manifest on source Bitbucket tag):

- migration still proceeds
- notes and traceability are preserved
- binary assets may be absent

## Idempotency and Retry Semantics

- Tags are migrated before releases.
- Checkpoint file stores terminal statuses per tag/release key.
- Existing complete destination releases are skipped.
- Existing incomplete destination releases are resumed.
- `failed-tags.txt` is always generated and can drive targeted retry.

## Output Artifacts

Each run creates:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Main files:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

When failures exist, `summary.json` includes a retry command for failed tags only.

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

## Exit Codes

- `0`: migration completed without failures
- `1`: at least one failure occurred
