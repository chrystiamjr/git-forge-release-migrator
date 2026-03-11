---
sidebar_position: 5
title: demo
---

Run a local simulation that exercises the CLI flow and artifact generation without real forge credentials.

## Syntax

```bash
gfrm demo [options]
```

## Typical use

```bash
gfrm demo --demo-releases 10 --demo-sleep-seconds 0.5
```

## Why use it

- verify local packaging and CLI behavior
- inspect artifact layout under `migration-results/`
- test summary and retry behavior without touching production repositories
