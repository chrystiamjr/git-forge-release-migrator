---
sidebar_position: 4
title: Localização dos Arquivos
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

Esses são os arquivos públicos de referência para diagnose e retry. Runtime events podem expor o mesmo estado para
observabilidade, mas operadores ainda devem ler esses arquivos e seguir `summary.json.retry_command` com `gfrm resume`.
