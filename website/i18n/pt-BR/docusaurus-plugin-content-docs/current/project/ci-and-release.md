---
sidebar_position: 3
title: CI and Release
---

## Pipelines principais

- `.github/workflows/quality-checks.yml` roda em `pull_request`
- `.github/workflows/release.yml` roda em `push` para `main`
- `.github/workflows/docs.yml` faz build e deploy do site Docusaurus

## Comportamento de release

- artefatos são gerados para Linux, Windows, macOS Intel e macOS Apple Silicon
- semantic-release publica a partir de `main`
- a documentação pública é gerada a partir de `website/`
