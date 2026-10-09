---
sidebar_position: 3
title: Bitbucket Behavior
---

Bitbucket Cloud does not map one-to-one to native GitHub or GitLab release semantics.

## Synthetic release model

A Bitbucket release is represented by:

- a tag
- notes
- downloads
- a manifest file named `.gfrm-release-<tag>.json`

Bitbucket downloads share one namespace per repository, so migrated assets are uploaded as `<tag>-<asset name>`
(for example `v1.2.0-app.zip`). This keeps same-named assets from different releases from replacing each other. The
manifest keeps the original asset name and links to the tag-scoped download.

## Legacy compatibility

When a source Bitbucket tag is missing a manifest, that condition alone must not hard-fail the migration.

## Operational implication

Treat downloads and the synthetic manifest as part of the same release unit when validating or troubleshooting a
Bitbucket migration.
