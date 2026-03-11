---
sidebar_position: 3
title: CI and Release
---

## Main pipelines

- `.github/workflows/quality-checks.yml` runs on `pull_request`
- `.github/workflows/release.yml` runs on `push` to `main`
- `.github/workflows/docs.yml` builds and deploys the Docusaurus site

## Release behavior

- release assets are built for Linux, Windows, macOS Intel, and macOS Apple Silicon
- semantic-release publishes from `main`
- docs are built from `website/`
