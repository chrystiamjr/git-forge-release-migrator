---
sidebar_position: 1
title: Common Migrations
---

## Bootstrap inicial

```bash
gfrm setup
```

## GitLab para GitHub

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo"
```

## GitHub para Bitbucket Cloud

```bash
gfrm migrate \
  --source-provider github \
  --source-url "https://github.com/org/repo" \
  --target-provider bitbucket \
  --target-url "https://bitbucket.org/workspace/repo"
```

## Preview com dry-run

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --dry-run
```

## Saída JSON para automação

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --json \
  --no-banner \
  --quiet
```
