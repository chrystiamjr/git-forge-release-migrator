---
sidebar_position: 2
title: Install and Verify
---

Os binários de release do `gfrm` rodam em máquinas limpas. Você não precisa de Dart, FVM, Node ou Yarn no host de destino.

## Verifique os checksums

```bash
# Linux ou macOS com sha256sum
sha256sum --check checksums-sha256.txt

# macOS com shasum
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

## Notas para macOS

- Escolha `intel` ou `silicon` conforme o tipo da máquina.
- Se o Gatekeeper bloquear a execução após descompactar, use o fallback:

```bash
xattr -d com.apple.quarantine ./gfrm
```

Para assinatura e notarização, veja [macOS Release Artifacts](/guides/macos-release-artifacts).
