---
sidebar_position: 4
title: File Locations
---

## Arquivos de runtime

| Finalidade | Local padrão |
| --- | --- |
| Settings globais | `~/.config/gfrm/settings.yaml` |
| Override local | `./.gfrm/settings.yaml` |
| Arquivo de sessão | `./sessions/last-session.json` |
| Artefatos de execução | `./migration-results/<timestamp>/` |

## Artefatos esperados por execução

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`
