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

For macOS release signing and notarization details, see [macOS Release Artifacts](/guides/macos-release-artifacts).

## Docker

Run `gfrm` without installing Dart, FVM, or any runtime on the host. Only Docker is required.

**Build the image** (from the repository root, requires the source clone):

```bash
docker build -t gfrm .
```

**Run a migration:**

```bash
docker run --rm \
  -v "$(pwd)/migration-results:/app/migration-results" \
  -e GITHUB_TOKEN="$GITHUB_TOKEN" \
  -e GITLAB_TOKEN="$GITLAB_TOKEN" \
  gfrm migrate \
    --source-provider gitlab --source-repo owner/repo \
    --target-provider github --target-repo owner/repo
```

Mount `migration-results/` so artifacts persist after the container exits.
Pass forge tokens via `-e` — never embed them in the image.

**Resume a failed run:**

```bash
docker run --rm \
  -v "$(pwd)/migration-results:/app/migration-results" \
  -v "$(pwd)/sessions:/app/sessions" \
  -e GITHUB_TOKEN="$GITHUB_TOKEN" \
  -e GITLAB_TOKEN="$GITLAB_TOKEN" \
  gfrm resume --session sessions/<timestamp>
```

Mount `sessions/` as well so the saved session file is available for resume.
