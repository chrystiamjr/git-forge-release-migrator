---
sidebar_position: 4
title: File Locations
---

## Runtime files

| Purpose | Default location |
| --- | --- |
| Global settings | `~/.config/gfrm/settings.yaml` |
| Local settings override | `./.gfrm/settings.yaml` |
| Session file | `./sessions/last-session.json` |
| Work artifacts | `./migration-results/<timestamp>/` |

## Expected artifacts per run

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`
