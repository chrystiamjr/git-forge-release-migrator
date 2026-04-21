---
sidebar_position: 4
title: Artefatos e Sessões
---

Cada execução grava artefatos em um diretório de trabalho com timestamp:

```text
migration-results/<timestamp>/
```

Artefatos obrigatórios:

- `migration-log.jsonl`
- `summary.json`
- `failed-tags.txt`

Esses arquivos continuam sendo o contrato operacional público de cada execução. Runtime events podem espelhar o mesmo
estado para consumidores internos, mas operadores ainda devem tratar esses artefatos e `gfrm resume` como fonte de
verdade.

## `summary.json`

Expectativas:

- schema version `2`
- metadados do comando executado
- retry command quando houver falhas
- caminhos de artefatos que correspondem aos arquivos gravados na execução

### Estrutura e Campos

Cada `summary.json` inclui:

```json
{
  "schema_version": 2,
  "command": "migrate",
  "order": "GitHub -> GitLab",
  "source": "github.com/owner/repo",
  "target": "gitlab.com/owner/repo",
  "tag_range": {
    "from": "<start>",
    "to": "<end>"
  },
  "dry_run": false,
  "skip_tag_migration": false,
  "skip_release_migration": false,
  "skip_release_asset_migration": false,
  "counts": {
    "tags_created": 10,
    "tags_skipped": 2,
    "tags_failed": 1,
    "tags_would_create": 0,
    "releases_created": 8,
    "releases_updated": 0,
    "releases_skipped": 2,
    "releases_failed": 1,
    "releases_would_create": 0
  },
  "paths": {
    "jsonl_log": "migration-results/2026-04-20T20:30:00Z/migration-log.jsonl",
    "checkpoint": "migration-results/2026-04-20T20:30:00Z/.checkpoint",
    "workdir": "migration-results/2026-04-20T20:30:00Z",
    "failed_tags": "migration-results/2026-04-20T20:30:00Z/failed-tags.txt"
  },
  "failed_tags": ["v2.3.0", "v3.1.0"],
  "retry_command": "gfrm resume",
  "retry_command_shell": "bash"
}
```

**Campos principais:**

- `schema_version`: Versão do contrato (sempre `2`)
- `command`: Se foi `migrate` ou `resume`
- `order` e `source`/`target`: Referências do provider e repositório
- `tag_range`: Intervalo semver para filtragem de tags (`<start>` e `<end>` representam sem limite)
- `dry_run`: Se a execução estava em modo simulação
- **`skip_tag_migration`**: Se a migração de tags foi pulada (de `--skip-tags`)
- **`skip_release_migration`**: Se a migração de releases foi pulada (de `--skip-releases`)
- **`skip_release_asset_migration`**: Se a migração de assets de releases foi pulada (de `--skip-release-assets`)
- `counts`: Divisão dos resultados da migração
  - Tags/releases criadas, puladas, falhadas ou que seriam criadas (dry-run)
  - Apenas tags/releases não puladas pelos flags estão incluídas
- `paths`: Localizações de todos os artefatos
- `failed_tags`: Lista ordenada de tags que falharam (vazia se todas tiveram sucesso)
- `retry_command`: Comando de shell para retomar a migração (ex: `gfrm resume`)
- `retry_command_shell`: Dica de shell para o comando de retry (`bash` ou `powershell`)

**Impacto dos flags de skip em retry:**

Quando os flags `skip_*` são definidos, os contadores refletem itens que foram realmente migrados. Quando você retoma com `gfrm resume`:
- O contexto da sessão salva preserva os flags de skip do comando `migrate` inicial
- Itens que falharam da fase pulada não são retentados (ex: se `--skip-releases` foi definido, apenas falhas de tags estão em `failed-tags.txt`)
- Você pode alterar os flags de skip na retomada para mudar o que será retentado (ex: retentar release depois de corrigir um problema temporário de asset)

### Triagem e Retry

Campos comuns para inspecionar durante a triagem:

- `retry_command` para continuar a execução com `gfrm resume`
- `skip_tag_migration`, `skip_release_migration`, `skip_release_asset_migration` para entender quais fases estavam ativas
- contadores de tags e releases para entender se a execução parou antes ou depois do início da publicação
- lista `failed_tags` e arquivo `failed-tags.txt` para identificar quais itens precisam de atenção

Quando o forge de destino não tem o histórico de commits necessário para tags pendentes, `summary.json` registra a
falha de preflight e deve ser lido junto com `failed-tags.txt`. O comando de retry verificará novamente o histórico de commits antes de prosseguir.

## Runtime events

Este runtime também expõe um stream ordenado de eventos por execução para observabilidade, testes e futuros consumidores
de GUI.

- sinks suportados nesta entrega: console, JSONL, in-memory e reducer
- os payloads dos eventos podem espelhar mudanças de status e caminhos de artefatos como `summary.json` e `failed-tags.txt`
- runtime events complementam a observabilidade, mas não substituem `summary.json`, `failed-tags.txt`,
  `migration-log.jsonl` nem `gfrm resume`

## Arquivos de sessão

Por padrão, o estado retomável é salvo em `./sessions/last-session.json`, salvo se `--session-file` for usado.

Use `gfrm resume` para continuar trabalho incompleto. Não reexecute `migrate` apenas para recuperar uma execução parcial.
Se precisar diagnosticar por que um retry ainda não pode prosseguir, inspecione o arquivo de sessão junto com
`summary.json` e `migration-log.jsonl`.
