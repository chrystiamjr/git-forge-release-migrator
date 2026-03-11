---
sidebar_position: 1
title: Common Migrations
---

## First-time bootstrap

```bash
gfrm setup
```

## GitLab to GitHub

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo"
```

## GitHub to Bitbucket Cloud

```bash
gfrm migrate \
  --source-provider github \
  --source-url "https://github.com/org/repo" \
  --target-provider bitbucket \
  --target-url "https://bitbucket.org/workspace/repo"
```

## Dry-run preview

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --dry-run
```

## JSON output for automation

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
