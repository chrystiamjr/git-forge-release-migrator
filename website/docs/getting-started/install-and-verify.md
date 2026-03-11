---
sidebar_position: 2
title: Install and Verify
---

`gfrm` release binaries run on clean machines. You do not need Dart, FVM, Node, or Yarn on the target host.

## Verify checksums

```bash
# Linux or macOS with sha256sum
sha256sum --check checksums-sha256.txt

# macOS with shasum
shasum -a 256 --check checksums-sha256.txt
```

## macOS Intel

```bash
unzip gfrm-macos-intel.zip -d ./gfrm-macos-intel
cd ./gfrm-macos-intel
chmod +x ./gfrm
./gfrm --help
```

## macOS Apple Silicon

```bash
unzip gfrm-macos-silicon.zip -d ./gfrm-macos-silicon
cd ./gfrm-macos-silicon
chmod +x ./gfrm
./gfrm --help
```

## Linux

```bash
unzip gfrm-linux.zip -d ./gfrm-linux
cd ./gfrm-linux
chmod +x ./gfrm
./gfrm --help
```

## Windows (PowerShell)

```powershell
Expand-Archive .\gfrm-windows.zip -DestinationPath .\gfrm-windows
.\gfrm-windows\gfrm.exe --help
```

## macOS notes

- Choose `intel` or `silicon` based on the machine type.
- If Gatekeeper still blocks execution after unzip, use the troubleshooting fallback:

```bash
xattr -d com.apple.quarantine ./gfrm
```

For release signing and notarization details, see [macOS Release Artifacts](/guides/macos-release-artifacts).
