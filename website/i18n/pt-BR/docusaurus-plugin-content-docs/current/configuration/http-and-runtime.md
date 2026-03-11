---
sidebar_position: 3
title: HTTP and Runtime
---

As configurações HTTP avançadas vivem sob o perfil ativo.

```yaml
profiles:
  default:
    http:
      connect_timeout_ms: 10000
      receive_timeout_ms: 90000
      max_retries: 3
      retry_delay_ms: 750
```

| Setting | Padrão | Significado |
| --- | --- | --- |
| `connect_timeout_ms` | `10000` | Timeout de conexão |
| `receive_timeout_ms` | `90000` | Timeout de recebimento |
| `max_retries` | `3` | Tentativas de retry |
| `retry_delay_ms` | `750` | Delay base com backoff exponencial |

Comportamentos de runtime a preservar:

- tags migram antes de releases
- migrações same-provider são rejeitadas
- a seleção de releases é limitada a tags semver no formato `vX.Y.Z`
- itens concluídos são ignorados no resume
