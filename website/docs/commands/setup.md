---
sidebar_position: 3
title: setup
---

Interactive bootstrap for token configuration.

## Syntax

```bash
gfrm setup [options]
```

## Main options

- `--profile <name>`
- `--local`
- `--yes`
- `--force`

## What setup does

1. scans common shell startup files in read-only mode for known token env names
2. prompts for provider token strategy
3. writes global or local settings YAML

## Example

```bash
gfrm setup --profile work
```

Use `--yes` only when defaults are already acceptable and you do not want prompts.
