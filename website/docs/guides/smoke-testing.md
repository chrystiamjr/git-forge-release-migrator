---
sidebar_position: 5
title: Smoke Testing
---

This guide walks you through setting up and running a real end-to-end smoke test of `gfrm` against your own throwaway test repositories on GitHub, GitLab, and Bitbucket. The smoke test verifies that the binary actually performs a migration round-trip: fake releases created on the source, migrated to the target, artifacts validated, source cleaned up.

## What smoke testing covers here

- **Not** unit tests (run `dart test` under `dart_cli/`).
- **Not** the local `demo --dry-run` flow (no real forge I/O).
- **Yes**: the binary + a real source forge + a real target forge + your personal tokens + throwaway test repositories you control.

Expect each run to take 1–3 minutes per forge pair and to cost a handful of forge API requests.

## Prerequisites

- `gfrm` binary installed. See [install instructions](../getting-started/install-and-verify.md).
- Accounts on at least two forges (GitHub, GitLab, or Bitbucket Cloud — any pair works).
- Ability to create a private repository on each forge.

## 1. Create test repositories

Create one empty private repository per forge you want to test. Naming suggestion: `gfrm-test-source` and `gfrm-test-target` so intent is obvious. Only create the repositories you need for the pair you will exercise.

| Forge | Create at |
|---|---|
| GitHub | https://github.com/new |
| GitLab | https://gitlab.com/projects/new |
| Bitbucket Cloud | https://bitbucket.org/repo/create |

Keep every test repository **private** and **empty** (no README, no license). The fixture workflows will initialize what they need.

:::note Bitbucket requires a workspace
Unlike GitHub and GitLab, Bitbucket Cloud repositories must live inside a **workspace** — repositories cannot be created directly under a personal account. If you do not already have one, create it at https://bitbucket.org/account/workspaces/ before using the repo creation form. The workspace slug is the `{workspace}` segment in URLs like `https://bitbucket.org/{workspace}/{repo}`.

**Workspace plan gotcha:** a Bitbucket Cloud workspace that has exceeded its user limit (common on the Free plan) silently flips every repository inside it to **read-only** and the Git push fails with HTTP 402:

```
[ALERT] Your push failed because the account '<workspace>' has exceeded its
[ALERT] user limit and this repository is restricted to read-only access.
```

If you hit this, either remove inactive members or upgrade the plan at `https://bitbucket.org/<workspace>/workspace/settings/plans`, or pick a different workspace that has write enabled. `gfrm smoke` can only seed and tear down fixtures when pushes are accepted.

**Creating a new workspace** as an alternative is not a simple UI action anymore. Bitbucket removed the standalone "Create workspace" option — the `+ Create` dropdown only offers Repository/Project/Package/Snippet, and `https://bitbucket.org/workspaces/create` returns "Repository not found". New workspaces are now provisioned by creating a new Atlassian **organization** at `https://admin.atlassian.com/` and adding the Bitbucket product to it. Plan accordingly before committing to Bitbucket as a smoke forge.
:::

## 2. Install the fixture workflows

Copy the workflow files from this repository into each of your test repositories.

### GitHub

From `docs/smoke-tests/workflows/github/` copy both files into the test repo under `.github/workflows/`:

- [`create-fake-releases.example.yml`](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/smoke-tests/workflows/github/create-fake-releases.example.yml) → `.github/workflows/create-fake-releases.yml`
- [`cleanup-tags-and-releases.example.yml`](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/smoke-tests/workflows/github/cleanup-tags-and-releases.example.yml) → `.github/workflows/cleanup-tags-and-releases.yml`

Commit both on the default branch and push.

### GitLab

From `docs/smoke-tests/workflows/gitlab/` copy:

- [`gitlab-ci.example.yml`](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/smoke-tests/workflows/gitlab/gitlab-ci.example.yml) → `.gitlab-ci.yml` at the project root.

The file defines both `create_fake_releases` and `cleanup_tags_and_releases` as manual jobs.

Add a **masked** CI/CD variable on the test project:

- Name: `GITLAB_PERSONAL_TOKEN`
- Value: your personal access token (see section 3)
- Masked: yes
- Protected: no (so it is available to manual jobs on any branch)

Commit and push.

### Bitbucket Cloud

From `docs/smoke-tests/workflows/bitbucket/` copy:

- [`bitbucket-pipelines.example.yml`](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/smoke-tests/workflows/bitbucket/bitbucket-pipelines.example.yml) → `bitbucket-pipelines.yml` at the repo root.

Enable Pipelines on the repository: Repository settings → Pipelines → Settings → Enable.

Add a **Secured** repository variable:

- Name: `BITBUCKET_TOKEN`
- Value: Repository Access Token (see section 3)
- Secured: yes

Commit and push.

## 3. Generate personal tokens

You need a token per forge that participates in the smoke test.

### GitHub personal token

Minimum scopes verified on 2026-04-20:

- `repo` — read + create tags, releases, and release assets on the test repo
- `workflow` — trigger the fixture workflows via API

Generate a classic PAT at https://github.com/settings/tokens/new and mark these two scopes. Copy the token and expose it via the env var your `settings.yaml` references (default: `GH_TOKEN` or `GH_PERSONAL_TOKEN`).

If GitHub renames or splits these scopes, check the current list: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#personal-access-tokens-classic

**Fine-grained PAT alternative**: restrict the token to the single test repository and grant:

- Actions: read/write
- Contents: read/write
- Metadata: read (auto-granted)

### GitLab personal token

Minimum scopes verified on 2026-04-20:

- `api` — full REST API access (needed for release + pipeline endpoints)
- `read_repository`, `write_repository` — git push/pull over HTTPS

Generate at https://gitlab.com/-/user_settings/personal_access_tokens. Expose via the env var your `settings.yaml` references (default: `GITLAB_PERSONAL_TOKEN`).

If GitLab rescopes these, see: https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html#personal-access-token-scopes

**Project access token alternative**: scope the token to the single test project with Maintainer role and the same `api` + `write_repository` permissions.

### Bitbucket Repository Access Token

Minimum scopes verified on 2026-04-20:

- `repository:admin` — create/delete tags and downloads on the test repo
- `pipeline:write` — trigger custom pipelines via API
- `pipeline:variable` — if the fixture pipeline uses variables

Generate a Repository Access Token under the test repo's settings: **Repository settings → Access tokens → Create access token**.

If Bitbucket rescopes, see: https://support.atlassian.com/bitbucket-cloud/docs/repository-access-tokens/

:::caution Do not reuse an Atlassian account API token
Atlassian account API tokens (from `id.atlassian.com`) and legacy App Passwords will return `401 Token is invalid, expired, or not supported for this endpoint` against the Bitbucket REST API when sent as `Authorization: Bearer …`, which is the scheme `gfrm` uses. Generate a Repository Access Token (or Workspace Access Token) instead — they are narrower, safer, and the supported path.
:::

## 4. Configure the CLI

Run the one-time setup:

```bash
gfrm setup
```

Then set each provider's token env var name in `settings.yaml` (this binds the settings profile to where your token value is held):

```bash
gfrm settings set-token-env --provider github --env-name GH_PERSONAL_TOKEN
gfrm settings set-token-env --provider gitlab --env-name GITLAB_PERSONAL_TOKEN
gfrm settings set-token-env --provider bitbucket --env-name BITBUCKET_TOKEN
```

Confirm:

```bash
gfrm settings show
```

Token values in the output are redacted. You should see each env var name listed against the right provider.

## 5. Run the smoke test

### Basic round-trip

```bash
gfrm smoke \
  --source-provider github --source-url https://github.com/you/gfrm-test-source \
  --target-provider gitlab --target-url https://gitlab.com/you/gfrm-test-target
```

Expected output fingerprint:

- `Creating fixture on source ...` followed by poll updates until the workflow completes
- `Cooldown 15s (after setup)`
- The usual migrate output lines
- `Cooldown 15s (after migration)`
- `Cleaning up source ...`
- Final summary with commit hash and artifact paths

### Common pairs

```bash
# GitHub → GitLab (most common)
gfrm smoke --source-provider github --source-url <gh-src> --target-provider gitlab --target-url <gl-tgt>

# GitLab → GitHub
gfrm smoke --source-provider gitlab --source-url <gl-src> --target-provider github --target-url <gh-tgt>

# Bitbucket → GitHub
gfrm smoke --source-provider bitbucket --source-url <bb-src> --target-provider github --target-url <gh-tgt>

# Bitbucket → GitLab
gfrm smoke --source-provider bitbucket --source-url <bb-src> --target-provider gitlab --target-url <gl-tgt>

# GitHub → Bitbucket
gfrm smoke --source-provider github --source-url <gh-src> --target-provider bitbucket --target-url <bb-tgt>

# GitLab → Bitbucket
gfrm smoke --source-provider gitlab --source-url <gl-src> --target-provider bitbucket --target-url <bb-tgt>
```

Same-provider migrations (e.g. GitHub → GitHub) are **not** supported.

## 6. Interpret results

Artifacts land under the workdir you passed (or a timestamped subfolder of `.tmp/smoke/` by default):

- `summary.json` — `schema_version: 2`, `command: "migrate"`, `retry_command` filled only when a partial failure occurred.
- `failed-tags.txt` — empty for a clean run.
- `migration-log.jsonl` — one JSON event per step. Useful for post-mortems.

A successful smoke run exits 0. Any non-zero exit with a message pointing at one of the phases means something actionable — see the command reference for exit codes.

## 7. Troubleshooting {#troubleshooting}

### `403 Forbidden` from a forge

Most common cause: the test project was flagged by the forge's abuse detection after too many identical create/delete cycles. The fixture workflows in this repository mitigate that with per-run timestamp suffixes, but an already-flagged project stays blocked for a while.

Remedies:

1. Check `GET /user` with your token to confirm the token itself is fine:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" -H "PRIVATE-TOKEN: $GITLAB_PERSONAL_TOKEN" https://gitlab.com/api/v4/user
   ```
   200 → token is good, the project is throttled. Wait 12–24h.
2. Rotate to a fresh test repository under a different name.
3. Reduce cooldown aggression is _not_ a fix; raising it is. Try `--cooldown-seconds 30`.

### Fixture workflow not triggered

- Confirm the workflow file is on the default branch of the test repo.
- GitHub: confirm `workflow_dispatch` is present in the YAML and the token has `workflow` scope.
- GitLab: confirm the job rules allow `web` / `api` triggers and your token has `api` scope.
- Bitbucket: confirm Pipelines is enabled for the repo and the custom pipeline name matches.

### Migration succeeded, cleanup 403

The migration artifact is authoritative — inspect `summary.json`. Then manually trigger `cleanup-tags-and-releases` (or the equivalent pipeline) from the forge UI to return the source repository to an empty state.

### Token missing scopes

Error messages usually name the missing permission. Regenerate the token with the exact scopes listed in section 3 above. Double-check you did not accidentally pick a "fine-grained" PAT that is restricted to repos that do not include the test repo.

## 8. Cleanup and reset

After any run (or mid-debug):

- `gfrm smoke --skip-setup --skip-teardown ...` runs only the migrate phase — useful when you want to re-migrate without touching the source.
- Manual cleanup: trigger the fixture's `cleanup-tags-and-releases` workflow directly from the forge UI.
- Full reset: delete and recreate the test repository. The fixture workflow files are small; re-adding them is fast.
