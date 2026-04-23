---
sidebar_position: 2
title: Instalar e Validar
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

Para assinatura e notarização, veja [Artefatos de Release do macOS](/guides/macos-release-artifacts).

## Docker

Execute `gfrm` sem instalar Dart, FVM ou qualquer runtime no host. Apenas Docker é necessário.

**Build da imagem** (a partir da raiz do repositório clonado):

```bash
docker build -t gfrm .
```

**Executar uma migração:**

```bash
docker run --rm \
  -v "$(pwd)/migration-results:/app/migration-results" \
  -e GITHUB_TOKEN="$GITHUB_TOKEN" \
  -e GITLAB_TOKEN="$GITLAB_TOKEN" \
  gfrm migrate \
    --source-provider gitlab --source-repo owner/repo \
    --target-provider github --target-repo owner/repo
```

Monte `migration-results/` para que os artefatos persistam após o container encerrar.
Passe os tokens via `-e` — nunca os incorpore na imagem.

**Retomar uma execução com falha:**

```bash
docker run --rm \
  -v "$(pwd)/migration-results:/app/migration-results" \
  -v "$(pwd)/sessions:/app/sessions" \
  -e GITHUB_TOKEN="$GITHUB_TOKEN" \
  -e GITLAB_TOKEN="$GITLAB_TOKEN" \
  gfrm resume --session sessions/<timestamp>
```

Monte `sessions/` também para que o arquivo de sessão salvo esteja disponível para retomada.
