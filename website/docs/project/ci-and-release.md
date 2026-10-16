---
sidebar_position: 3
title: CI and Release
---

## Main pipelines

- `.github/workflows/quality-checks.yml` runs on `pull_request`
- `.github/workflows/release.yml` runs on `push` to `main`
- `.github/workflows/docs.yml` builds and deploys the Docusaurus site

## Ticket delivery gates

Local validation does not conclude a ticket. Delivery stops in Review with verified PR/YouTrack links until the maintainer reviews the current head and merges manually. In solo mode, a human `/reviewed` comment lets automation record the current head SHA in a persistent check; `/reviewed <sha>` explicitly selects the revision; bot approval is auxiliary. A new head invalidates either review mode; delayed automatic capture stays pending until a new comment or an explicit SHA is supplied.

Quality Checks compares production coverage with an isolated fixed-base measurement, builds changed EN/PT-BR docs before merge, and runs separate canonical GUI golden comparisons. The aggregate `ticket-validation` check requires core and visual success. Reports and image diagnostics are retained as CI artifacts; proposed baseline updates need human review.

The metadata-only Ticket Delivery workflow uses trusted default-branch code. Activation requires the owner's YouTrack secret/opt-in and required-check configuration after deployment. Native desktop and real forge smoke remain separate acceptance evidence.

See the [testing playbook](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/engineering/testing-playbook.md) and [delivery contract](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/engineering/ticket-delivery.md).

## Automated review progress

Each PR has one bot-owned **Required tests** comment that also shows review progress: waiting for CI, preparing,
evaluation queued or running, publishing, and complete/failed/cancelled/skipped. Stage updates include a UTC timestamp
and a link to checks or the review workflow. The status describes workflow stages, not a percentage or live model activity.

Updates follow the current commit and workflow attempt, preserve test evidence, and do not replace human review.
Progress steps have one-minute deadlines; their errors remain visible in Actions without stopping the review.
The verdict publication job is not limited by that progress deadline.
The bot edits the same comment instead of posting a new comment for every stage. Reviewer changes activate after
merge into the default branch. If a status cannot be updated, follow its workflow link for the current state.

## Release behavior

- release assets are built for Linux, Windows, macOS Intel, and macOS Apple Silicon
- semantic-release publishes from `main`
- docs are built from `website/`
