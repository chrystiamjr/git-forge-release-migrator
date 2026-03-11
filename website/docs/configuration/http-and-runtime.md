---
sidebar_position: 3
title: HTTP and Runtime
---

Advanced HTTP settings live under the active profile.

```yaml
profiles:
  default:
    http:
      connect_timeout_ms: 10000
      receive_timeout_ms: 90000
      max_retries: 3
      retry_delay_ms: 750
```

| Setting | Default | Meaning |
| --- | --- | --- |
| `connect_timeout_ms` | `10000` | Connection timeout |
| `receive_timeout_ms` | `90000` | Response receive timeout |
| `max_retries` | `3` | Request retry attempts |
| `retry_delay_ms` | `750` | Base retry delay with exponential backoff |

Runtime behavior to preserve:

- tags migrate before releases
- same-provider migrations are rejected
- release selection is limited to semver tags in `vX.Y.Z` format
- completed items are skipped on resume
