---
sidebar_position: 4
title: Artefatos de Release no macOS
---

## Escolha o artefato correto

- `gfrm-macos-intel.zip` para Macs Intel
- `gfrm-macos-silicon.zip` para Macs Apple Silicon

## Modos de segurança no CI

O workflow de release suporta:

- `MACOS_RELEASE_SECURITY_MODE=permissive`
- `MACOS_RELEASE_SECURITY_MODE=strict`

No modo estrito, credenciais ausentes de assinatura ou notarização falham os jobs de macOS.

## Troubleshooting local

Se o Gatekeeper ainda bloquear a execução após descompactar:

```bash
xattr -d com.apple.quarantine ./gfrm
```
