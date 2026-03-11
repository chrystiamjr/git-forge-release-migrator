---
sidebar_position: 4
title: macOS Release Artifacts
---

## Choose the correct artifact

- `gfrm-macos-intel.zip` for Intel Macs
- `gfrm-macos-silicon.zip` for Apple Silicon Macs

## Security modes in CI

The release workflow supports:

- `MACOS_RELEASE_SECURITY_MODE=permissive`
- `MACOS_RELEASE_SECURITY_MODE=strict`

In strict mode, missing signing or notarization credentials fail the macOS release jobs.

## Local troubleshooting

If Gatekeeper still blocks execution after unzip:

```bash
xattr -d com.apple.quarantine ./gfrm
```
