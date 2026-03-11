# Git Forge Release Migrator (gfrm)

[![License](https://img.shields.io/badge/license-MIT-green)](../LICENSE)
[![Release](https://img.shields.io/badge/release-semantic--release-informational)](../../release.config.cjs)
[![Flutter SDK](https://img.shields.io/badge/Flutter%20SDK-3.41.0-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart SDK](https://img.shields.io/badge/Dart%20SDK-3.11.0-0175C2?logo=dart&logoColor=white)](https://dart.dev/)

`gfrm` é uma CLI cross-forge resiliente que migra **tags, releases, notas e artefatos** entre GitHub, GitLab e Bitbucket
com retries idempotentes.

## Como Funciona

O `gfrm` migra **tags primeiro**, depois **releases** (idempotente, baseado em checkpoints). Cada execução grava um
diretório de artefatos com timestamp contendo log, sumário e lista de tags com falha. Execuções interrompidas podem ser
retomadas com `gfrm resume` — itens concluídos são ignorados automaticamente.

## Quick Start

1. Baixe o artefato para o seu sistema operacional na [página de releases](/releases).
2. Descompacte e torne o binário executável (macOS/Linux: `chmod +x ./gfrm`).
3. Configure suas credenciais uma única vez:
   ```bash
   ./gfrm setup
   ```
4. Execute sua primeira migração:
   ```bash
   ./gfrm migrate \
     --source-provider gitlab \
     --source-url "https://gitlab.com/group/project" \
     --target-provider github \
     --target-url "https://github.com/org/repo"
   ```
5. Se a execução for interrompida, retome com:
   ```bash
   ./gfrm resume
   ```

## Documentação

Para mais detalhes de uso e documentação em outros idiomas, use os docs sob [/docs](../..) com a pasta do idioma
desejado.

- Documentações em inglês: [docs/en_us](../en_us)
- Documentações em português: [docs/pt_br](../pt_br)
- Guia de desenvolvimento/runtime: [dart_cli/README.md](../../dart_cli/README.md)

> O Dart SDK é gerenciado via [FVM](https://fvm.app/) (`3.41.0` / Dart `3.11.0`). O FVM também prepara o terreno para
> uma futura aplicação Flutter com interface gráfica.

## Matriz de Suporte

Pares cross-forge suportados:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> github` (Bitbucket Cloud)
- `gitlab -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> gitlab` (Bitbucket Cloud)

Não suportado nesta fase:

- migração same-provider (`github->github`, `gitlab->gitlab`, `bitbucket->bitbucket`)
- Bitbucket Data Center / Server

## Executando A CLI Compilada

Artefatos de release:

- `gfrm-macos-intel.zip`
- `gfrm-macos-silicon.zip`
- `gfrm-linux.zip`
- `gfrm-windows.zip`
- `checksums-sha256.txt` — checksums SHA256 para todos os artefatos zip

Os binários compilados do `gfrm` rodam em máquinas limpas sem Dart/FVM/Node/Yarn.

Para verificar a integridade antes de executar:

```bash
# macOS / Linux
sha256sum --check checksums-sha256.txt

# macOS (shasum)
shasum -a 256 --check checksums-sha256.txt
```

macOS (Intel):

```bash
unzip gfrm-macos-intel.zip -d ./gfrm-macos-intel
cd ./gfrm-macos-intel
chmod +x ./gfrm
./gfrm --help
```

macOS (Apple Silicon):

```bash
unzip gfrm-macos-silicon.zip -d ./gfrm-macos-silicon
cd ./gfrm-macos-silicon
chmod +x ./gfrm
./gfrm --help
```

Linux:

```bash
unzip gfrm-linux.zip -d ./gfrm-linux
cd ./gfrm-linux
chmod +x ./gfrm
./gfrm --help
```

Windows (PowerShell):

```powershell
Expand-Archive .\gfrm-windows.zip -DestinationPath .\gfrm-windows
.\gfrm-windows\gfrm.exe --help
```

Notas:

- macOS: escolha o artefato `intel` ou `silicon` conforme o tipo do Mac.
- Fallback de troubleshooting no macOS: `xattr -d com.apple.quarantine ./gfrm`.
- Em `MACOS_RELEASE_SECURITY_MODE=strict`, o release falha quando assinatura/notarização não é concluída.

## Visão Geral de Comandos

- `gfrm migrate`: inicia migração com parâmetros explícitos de source/target
- `gfrm resume`: retoma uma migração com sessão salva
- `gfrm demo`: fluxo de simulação local
- `gfrm setup`: bootstrap interativo para perfil de settings
- `gfrm settings`: gerenciamento de tokens/perfis

## Perfis de Settings

Comandos de settings:

```bash
gfrm settings init [--profile <nome>] [--local] [--yes]
gfrm settings set-token-env --provider <github|gitlab|bitbucket> --env-name <ENV_NAME> [--profile <nome>] [--local]
gfrm settings set-token-plain --provider <github|gitlab|bitbucket> [--token <valor>] [--profile <nome>] [--local]
gfrm settings unset-token --provider <github|gitlab|bitbucket> [--profile <nome>] [--local]
gfrm settings show [--profile <nome>]
```

Arquivos de settings:

- global: `~/.config/gfrm/settings.yaml` (ou `XDG_CONFIG_HOME/gfrm/settings.yaml`)
- override local: `./.gfrm/settings.yaml`

Ordem de resolução de perfil:

1. `--settings-profile`
2. `defaults.profile` em settings
3. `default`

Ordem padrão de resolução de token:

1. `migrate` e `resume`: flags `--source-token` / `--target-token` (ocultos, legado — maior precedência quando fornecidos)
2. `migrate`: token do provider em settings (`token_env`, depois `token_plain`)
3. `migrate`: aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)
4. `resume`: contexto de token da sessão
5. `resume`: token do provider em settings (`token_env`, depois `token_plain`)
6. `resume`: aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)

## Exemplos de Migração

Inicializar settings quando o projeto ainda não tem configuração:

```bash
gfrm setup
```

Executar migração com perfil de settings configurado:

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --settings-profile default \
  --from-tag v1.0.0 \
  --to-tag v2.0.0
```

Dry-run (valida e simula sem escrever no destino):

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --dry-run
```

Retomar por sessão (arquivo padrão é `./sessions/last-session.json` quando omitido):

```bash
gfrm resume --session-file ./sessions/last-session.json
```

## Artefatos e Retry

Cada execução escreve em:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Artefatos:

- `migration-log.jsonl`
- `summary.json` (schema v2, inclui `schema_version` e comando executado)
- `failed-tags.txt`

Quando existem falhas, `summary.json` inclui `retry_command` usando `gfrm resume`.

## Avisos Diagnósticos

O `gfrm` escreve avisos no `stderr` em duas situações sem interromper a migração:

- **Entrada de checkpoint corrompida** — se uma linha `.jsonl` do checkpoint não puder ser processada, um aviso é exibido e a entrada é ignorada. As entradas restantes ainda são carregadas.
- **Arquivo de settings malformado** — se um arquivo `settings.yaml` falhar no parsing YAML, o `gfrm` tenta novamente como JSON e emite um aviso. Se ambos falharem, os valores padrão são utilizados.

Em ambos os casos o formato do aviso é:

```
[gfrm] warning: <descrição>
```

## Códigos de Saída

- `0`: execução bem-sucedida (todos os itens migrados ou concluídos anteriormente)
- diferente de zero: falha de validação ou operacional (consulte `summary.json` e `failed-tags.txt`)
