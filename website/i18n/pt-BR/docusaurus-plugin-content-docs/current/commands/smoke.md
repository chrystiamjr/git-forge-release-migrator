---
sidebar_position: 6
title: smoke
---

Executa um teste smoke real de ponta a ponta contra repositórios de teste descartáveis em dois forges. Dispara os workflows de CI que criam releases falsos na origem, migra para o destino, valida os artefatos e limpa a origem.

Veja também: [Guia de smoke testing](../guides/smoke-testing.md).

## Sintaxe

```bash
gfrm smoke \
  --source-provider <github|gitlab|bitbucket> \
  --source-url <url-do-repo> \
  --target-provider <github|gitlab|bitbucket> \
  --target-url <url-do-repo> \
  [opções]
```

## Uso típico

```bash
gfrm smoke \
  --source-provider github --source-url https://github.com/voce/gfrm-test-source \
  --target-provider gitlab --target-url https://gitlab.com/voce/gfrm-test-target
```

## O que faz

1. Dispara o workflow `create-fake-releases` no forge de origem e espera terminar.
2. Cooldown (padrão 15s) para evitar heurísticas de abuso dos forges.
3. Executa `gfrm migrate` da origem para o destino.
4. Valida o contrato de artefatos (`summary.json`, `failed-tags.txt`, `migration-log.jsonl`).
5. Cooldown.
6. Dispara o workflow `cleanup-tags-and-releases` na origem.

## Pré-requisitos

Antes de rodar `gfrm smoke`:

- Dois repositórios de teste descartáveis, um por forge, seguindo o [guia de smoke testing](../guides/smoke-testing.md).
- Workflows de fixture instalados em cada repositório de teste (copiados de `docs/smoke-tests/workflows/<forge>/`).
- Tokens pessoais disponíveis via `settings.yaml` (veja `gfrm setup`).

## Opções

### Obrigatórias

| Flag | Descrição |
|---|---|
| `--source-provider` | `github`, `gitlab` ou `bitbucket` |
| `--source-url` | URL completa do repo de teste de origem |
| `--target-provider` | `github`, `gitlab` ou `bitbucket` |
| `--target-url` | URL completa do repo de teste de destino |

### Orquestração

| Flag | Padrão | Descrição |
|---|---|---|
| `--mode` | `happy-path` | Modo de execução: `happy-path`, `contract-check`, `partial-failure-resume` |
| `--skip-setup` | off | Pula o passo de criar fixture. Use quando a origem já está populada |
| `--skip-teardown` | off | Pula o passo de cleanup. Deixa a origem populada para inspeção |
| `--cooldown-seconds` | `15` | Segundos entre fases (env: `GFRM_SMOKE_COOLDOWN`) |
| `--poll-interval` | `10` | Segundos entre polls de status do CI |
| `--poll-timeout` | `300` | Segundos máximos de espera de um workflow antes de falhar |

### Passthrough para a migração

| Flag | Descrição |
|---|---|
| `--settings-profile` | Nome do profile em `settings.yaml` |
| `--workdir` | Diretório raiz para os artefatos do smoke |
| `--quiet` | Reduz a saída interativa |
| `--json` | Emite logs em JSON |

Qualquer flag aceita pelo `gfrm migrate` também é aceita pelo `gfrm smoke` e é encaminhada para a fase de migração.

## Modos

| Modo | Comportamento |
|---|---|
| `happy-path` | Fluxo completo. Espera que nenhuma falha parcial ocorra |
| `contract-check` | happy-path + valida que `summary.retry_command` está vazio |
| `partial-failure-resume` | happy-path + segue `summary.retry_command` ou executa um `gfrm resume` sintético contra a primeira tag da origem |

## Exemplos

### GitHub → GitLab (modo padrão)

```bash
gfrm smoke \
  --source-provider github --source-url https://github.com/voce/gfrm-test-source \
  --target-provider gitlab --target-url https://gitlab.com/voce/gfrm-test-target
```

### Manter origem populada para debug

```bash
gfrm smoke \
  --source-provider github --source-url https://github.com/voce/gfrm-test-source \
  --target-provider gitlab --target-url https://gitlab.com/voce/gfrm-test-target \
  --skip-teardown
```

### Contra origem já preparada

```bash
gfrm smoke \
  --skip-setup \
  --source-provider gitlab --source-url https://gitlab.com/voce/gfrm-test-source \
  --target-provider github --target-url https://github.com/voce/gfrm-test-target
```

### Contract check em CI

```bash
GFRM_SMOKE_COOLDOWN=0 gfrm smoke \
  --mode contract-check \
  --source-provider bitbucket --source-url https://bitbucket.org/voce/gfrm-test-source \
  --target-provider github --target-url https://github.com/voce/gfrm-test-target
```

## Códigos de saída

- `0` — round-trip completo funcionou, artefatos válidos
- `1` — alguma fase falhou (disparo de fixture, migração, validação ou teardown). Veja `migration-log.jsonl` e `summary.json` no workdir
- `2` — argumentos inválidos

## Troubleshooting

- **403 vindo de um forge** — seu projeto de teste pode estar com rate limit. Espere 24h ou rode em um repo de teste novo. Veja o [guia de smoke testing](../guides/smoke-testing.md#troubleshooting).
- **Workflow de CI não disparou** — confirme que o arquivo do workflow está no branch padrão e que o trigger (`workflow_dispatch`/`custom`) está habilitado.
- **Cleanup falhou** — rode `gfrm smoke --skip-setup --skip-teardown` e depois dispare manualmente o workflow de cleanup pela UI do forge.
