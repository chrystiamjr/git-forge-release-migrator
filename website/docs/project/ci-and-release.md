---
sidebar_position: 3
title: CI and Release
---

## Main pipelines

- `.github/workflows/quality-checks.yml` runs on `pull_request`
- `.github/workflows/release.yml` runs on `push` to `main`
- `.github/workflows/docs.yml` builds and deploys the Docusaurus site

## Ticket delivery gates

Local validation does not conclude a ticket. Delivery stops in Review with verified PR/YouTrack links until the maintainer reviews the current head and merges manually. In solo mode, a human `/reviewed <sha>` comment records the decision; bot approval is auxiliary.

Quality Checks compares production coverage with an isolated fixed-base measurement, builds changed EN/PT-BR docs before merge, and runs separate canonical GUI golden comparisons. The aggregate `ticket-validation` check requires core and visual success. Reports and image diagnostics are retained as CI artifacts; proposed baseline updates need human review.

The metadata-only Ticket Delivery workflow uses trusted default-branch code. Activation requires the owner's YouTrack secret/opt-in and required-check configuration after deployment. Native desktop and real forge smoke remain separate acceptance evidence.

See the [testing playbook](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/engineering/testing-playbook.md) and [delivery contract](https://github.com/chrystiamjr/git-forge-release-migrator/blob/main/docs/engineering/ticket-delivery.md).

## Release behavior

- release assets are built for Linux, Windows, macOS Intel, and macOS Apple Silicon
- semantic-release publishes from `main`
- docs are built from `website/`
