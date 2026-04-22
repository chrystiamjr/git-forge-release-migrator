# Smoke testing templates

This folder ships the CI fixtures and documentation used by `gfrm smoke` to exercise a real end-to-end migration against throwaway test repositories on GitHub, GitLab, and Bitbucket.

See the user guide for step-by-step setup:
→ [Smoke testing guide](../../website/docs/guides/smoke-testing.md)

And the command reference:
→ [`gfrm smoke` reference](../../website/docs/commands/smoke.md)

## What is in here

```
docs/smoke-tests/
├── README.md                                             ← this file
└── workflows/
    ├── github/
    │   ├── create-fake-releases.example.yml
    │   └── cleanup-tags-and-releases.example.yml
    ├── gitlab/
    │   └── gitlab-ci.example.yml
    └── bitbucket/
        └── bitbucket-pipelines.example.yml
```

Each file is a template you copy into your own test repository on the matching forge, then commit and push. `gfrm smoke` dispatches the relevant workflow or pipeline through the forge's REST API, waits for it to complete, runs the migration, and finally dispatches the cleanup workflow to return the test repository to an empty state.

## Supported forges

- **GitHub Actions** — two separate `workflow_dispatch` workflows.
- **GitLab CI** — one `.gitlab-ci.yml` with two manual jobs (`create_fake_releases`, `cleanup_tags_and_releases`).
- **Bitbucket Pipelines** — one `bitbucket-pipelines.yml` with two custom pipelines (`create_fake_releases`, `cleanup_tags_and_releases`). Bitbucket Cloud only; Bitbucket Data Center / Server is not supported.

## Key design choices

- **Per-run timestamp suffix** on every tag identifier. Prevents forge abuse heuristics from flagging the test project for creating and deleting identical tag names repeatedly.
- **Cleanup enumerates, it does not glob**. All three workflows iterate the full list of tags/releases and delete each one, so stale data from previous runs is always cleared.
- **No production secrets**. The fixture workflows use scoped, short-lived tokens (Repository Access Tokens on Bitbucket, `workflow` scope on GitHub, `api` scope on GitLab). See the user guide for exact scope requirements.

## Who should use this

Anyone verifying a new release of `gfrm` against real forges before relying on it for production migration. Includes:

- Contributors validating a change to the migration engine.
- Downstream integrators piloting `gfrm` against their own forge pair before committing to a migration.
- CI pipelines that want to continuously smoke-test the binary against a known-good fixture.
