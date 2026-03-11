# Referência da CLI (Português)

Este documento reflete o contrato atual da CLI Dart (`gfrm`).

## Comandos Canônicos

```bash
./bin/gfrm migrate [opções]
./bin/gfrm resume [opções]
./bin/gfrm demo [opções]
./bin/gfrm setup [opções]
./bin/gfrm settings <ação> [opções]
```

> Em desenvolvimento local, prefixe os comandos com `./bin/gfrm`. Ao usar um artefato de release compilado, use `./gfrm` (ou `.\gfrm.exe` no Windows) diretamente. Todos os exemplos abaixo usam `gfrm` sem prefixo de caminho por brevidade.

## Desenvolvimento Local (Yarn Primeiro)

Verificações locais recomendadas a partir da raiz do repositório:

```bash
yarn lint:dart
yarn test:dart
yarn coverage:dart
./scripts/smoke-test.sh
```

Comandos Dart diretos ainda funcionam, mas a documentação prioriza os scripts `yarn` para o desenvolvimento local do dia a dia.

Saídas de coverage:

- `dart_cli/coverage/lcov.info` para ferramentas compatíveis com LCOV
- `dart_cli/coverage/coverage_html.zip` como artefato HTML publicado no CI
- `dart_cli/coverage/html/index.html` para navegação local após `yarn coverage:dart`

## Executando Artefatos de CI

Artefatos gerados pelo CI:

- `gfrm-macos-intel.zip` contendo `gfrm` (Macs Intel)
- `gfrm-macos-silicon.zip` contendo `gfrm` (Macs Apple Silicon)
- `gfrm-linux.zip` contendo `gfrm`
- `gfrm-windows.zip` contendo `gfrm.exe`
- `checksums-sha256.txt` — checksums SHA256 para todos os artefatos zip

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

- O workflow de release suporta o modo de segurança macOS permissivo/estrito (`MACOS_RELEASE_SECURITY_MODE`) para assinatura/notarização.
- No modo estrito, os jobs de release do macOS falham quando as credenciais de assinatura/notarização estão ausentes ou a notarização falha.
- Se o Gatekeeper ainda bloquear a execução, use o fallback de troubleshooting: `xattr -d com.apple.quarantine ./gfrm`.
- Avisos do Windows SmartScreen são esperados enquanto os binários não estiverem assinados.

## Providers e Aliases

Providers suportados:

- `github` (alias: `gh`)
- `gitlab` (alias: `gl`)
- `bitbucket` (alias: `bb`, somente Bitbucket Cloud)

Pares cross-forge suportados:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket`
- `bitbucket -> github`
- `gitlab -> bitbucket`
- `bitbucket -> gitlab`

Não suportado:

- migrações same-provider
- Bitbucket Data Center / Server

## Exemplos de Uso

### Migração básica (GitLab → GitHub)

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo"
```

### Migração com intervalo de tags

Migra apenas releases entre duas tags (inclusive):

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --from-tag v1.0.0 \
  --to-tag v2.5.0
```

### Dry-run antes de migrar

Valida acesso ao source/target e simula a migração sem escrever no destino:

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --dry-run
```

### Retomar uma migração interrompida

Se uma execução foi interrompida, retome a partir da última sessão salva:

```bash
gfrm resume
```

Ou especifique o arquivo de sessão explicitamente:

```bash
gfrm resume --session-file ./sessions/my-session.json
```

### Migrar usando tokens explícitos (sem settings)

Passe tokens diretamente via variáveis de ambiente:

```bash
GFRM_SOURCE_TOKEN=glpat-xxx GFRM_TARGET_TOKEN=ghp-yyy gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo"
```

## `migrate`

Inicia uma migração a partir de parâmetros explícitos de source e target.

Sintaxe:

```bash
gfrm migrate \
  --source-provider <github|gitlab|bitbucket> \
  --source-url <url> \
  --target-provider <github|gitlab|bitbucket> \
  --target-url <url> \
  [opções]
```

Obrigatórios:

- `--source-provider`
- `--source-url`
- `--target-provider`
- `--target-url`

Fontes de token (em ordem):

1. token de settings (`token_env`, depois `token_plain`)
2. aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)

Nota de compatibilidade legada:

- As flags ocultas `--source-token` e `--target-token` ainda sobrepõem a resolução quando fornecidas explicitamente, mas não fazem parte do fluxo público recomendado.

Opções principais:

- `--settings-profile <nome>`
- `--skip-tags`
- `--from-tag <tag>`
- `--to-tag <tag>`
- `--workdir <dir>`
- `--log-file <caminho>`
- `--checkpoint-file <caminho>`
- `--tags-file <caminho>`
- `--download-workers <1..16>` (padrão: `4`)
- `--release-workers <1..8>` (padrão: `1`)
- `--dry-run`
- `--save-session` (padrão: habilitado)
- `--no-save-session`
- `--session-file <caminho>`
- `--session-token-mode <env|plain>` (padrão: `env`)
- `--session-source-token-env <nome>` (padrão: `GFRM_SOURCE_TOKEN`)
- `--session-target-token-env <nome>` (padrão: `GFRM_TARGET_TOKEN`)
- `--no-banner`
- `--quiet`
- `--json`
- `--progress-bar`

Regras de validação:

- `--download-workers` deve ser `1..16`
- `--release-workers` deve ser `1..8`
- se ambos `--from-tag` e `--to-tag` forem definidos, `from <= to`

## `resume`

Retoma a partir de um arquivo de sessão salvo.

Sintaxe:

```bash
gfrm resume [opções]
```

Opções principais:

- `--session-file <caminho>` (padrão quando omitido: `./sessions/last-session.json`)
- `--settings-profile <nome>`
- `--skip-tags`
- `--from-tag <tag>`
- `--to-tag <tag>`
- `--workdir <dir>`
- `--log-file <caminho>`
- `--checkpoint-file <caminho>`
- `--tags-file <caminho>`
- `--download-workers <1..16>`
- `--release-workers <1..8>`
- `--dry-run`
- `--save-session` (padrão: habilitado)
- `--no-save-session`
- `--session-token-mode <env|plain>`
- `--session-source-token-env <nome>`
- `--session-target-token-env <nome>`
- `--no-banner`
- `--quiet`
- `--json`
- `--progress-bar`

Fontes de token (em ordem):

1. token do contexto de sessão (`source_token` ou `source_token_env`, o mesmo para target)
2. token de settings (`token_env`, depois `token_plain`)
3. aliases de ambiente (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, aliases por provider)

Se um token for necessário para o fluxo de resume, configure-o via settings ou aliases de ambiente antes de executar `resume`.

## `demo`

Executa um fluxo de simulação local com releases sintéticas — nenhum forge real de source ou target é necessário. Útil para verificar o comportamento da CLI, a estrutura de artefatos e o ajuste de workers sem credenciais.

Sintaxe:

```bash
gfrm demo [opções]
```

Exemplo:

```bash
gfrm demo --demo-releases 10 --demo-sleep-seconds 0.5
```

Opções principais:

- `--demo-releases <1..100>` (padrão: `5`) — número de releases sintéticas a simular
- `--demo-sleep-seconds <segundos>` (padrão: `1.0`, deve ser `>= 0`) — atraso de processamento simulado por release
- `--skip-tags`
- `--dry-run`
- `--workdir`, `--log-file`, `--checkpoint-file`, `--tags-file`
- `--download-workers`, `--release-workers`
- `--session-file`, `--session-token-mode`, `--session-source-token-env`, `--session-target-token-env`
- `--no-banner`, `--quiet`, `--json`, `--progress-bar`

## `setup`

Bootstrap interativo para configuração inicial de settings.

Sintaxe:

```bash
gfrm setup [opções]
```

Opções:

- `--profile <nome>`
- `--local` (escreve em `./.gfrm/settings.yaml`)
- `--yes` (padrões não interativos)
- `--force` (executa o setup mesmo quando mapeamentos de token existentes são detectados)

## `settings`

Ações de settings:

```bash
gfrm settings init [--profile <nome>] [--local] [--yes]
gfrm settings set-token-env --provider <github|gitlab|bitbucket> --env-name <ENV_NAME> [--profile <nome>] [--local]
gfrm settings set-token-plain --provider <github|gitlab|bitbucket> [--token <valor>] [--profile <nome>] [--local]
gfrm settings unset-token --provider <github|gitlab|bitbucket> [--profile <nome>] [--local]
gfrm settings show [--profile <nome>]
```

Comportamento:

- caminho global de settings: `~/.config/gfrm/settings.yaml` (ou `XDG_CONFIG_HOME/gfrm/settings.yaml`)
- caminho de override local: `./.gfrm/settings.yaml`
- settings efetivas = deep-merge(global, local)
- `settings show` mascara `token_plain`
- `settings init` escaneia arquivos de shell em modo somente leitura (`.zshrc`, `.zprofile`, `.bashrc`, `.bash_profile`)
- `migrate` e `resume` foram desenhados para resolver tokens via settings, contexto de sessão ou aliases de ambiente sem exigir flags explícitas de token

Resolução de perfil:

1. `--settings-profile` explícito (para `migrate`/`resume`)
2. `defaults.profile` de settings
3. `default`

## Invariantes de Runtime

- a ordem de migração é sempre tags primeiro
- a seleção de releases é somente semver (`vX.Y.Z`)
- semântica de checkpoint/idempotência e retry são preservadas
- artefatos de execução são sempre gerados em um workdir com timestamp

## Avisos Diagnósticos

O `gfrm` escreve avisos no `stderr` em duas situações sem interromper a migração:

- **Entrada de checkpoint corrompida** — se uma linha `.jsonl` do checkpoint não puder ser processada, um aviso é exibido e a entrada é ignorada. As entradas restantes ainda são carregadas.
- **Arquivo de settings malformado** — se um arquivo `settings.yaml` falhar no parsing YAML, o `gfrm` tenta novamente como JSON e emite um aviso. Se ambos falharem, os valores padrão são utilizados.

Formato do aviso:

```
[gfrm] warning: <descrição>
```

## Artefatos

Cada execução escreve em:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Arquivos principais:

- `migration-log.jsonl` — log JSON delimitado por nova linha; um objeto de evento por linha
- `summary.json` — sumário final da execução (schema v2)
- `failed-tags.txt` — um nome de tag por linha; vazio quando todas as tags foram concluídas com sucesso

Campos de `summary.json`:

- `schema_version`: `2`
- `command`: subcomando executado (`migrate`, `resume`, `demo`)
- `status`: resultado geral da execução
- `retry_command`: comando `gfrm resume` pré-construído para retentar falhas (presente somente quando `failed-tags.txt` não está vazio)

Formato de `failed-tags.txt`:

```text
v1.2.0
v1.3.0
```

Quando este arquivo não está vazio, `summary.json` incluirá um `retry_command` pronto para execução.

## Códigos de Saída

- `0`: execução bem-sucedida
- diferente de zero: falha de validação ou operacional

## Problemas Comuns

**Token não encontrado**
O `gfrm` sai com código não-zero e um erro de validação quando nenhum token é resolvido para source ou target. Execute `gfrm settings show` para inspecionar os mapeamentos de token atuais, ou passe tokens via `GFRM_SOURCE_TOKEN` / `GFRM_TARGET_TOKEN`.

**Par de providers não suportado**
Migrações same-provider (`github -> github`, etc.) e Bitbucket Data Center não são suportados. A CLI sai imediatamente com um erro de validação.

**Ordenação de `--from-tag` / `--to-tag`**
Se ambos forem definidos, `from` deve ser `<=` `to` (ordem semver). Invertê-los causa uma falha de validação antes de qualquer migração iniciar.

**Bloqueio do macOS Gatekeeper**
Se o macOS bloquear a execução após descompactar, execute: `xattr -d com.apple.quarantine ./gfrm`

**Resume após perda do arquivo de sessão**
Se `./sessions/last-session.json` estiver ausente, `gfrm resume` sai com um erro. Inicie uma nova migração do zero com `gfrm migrate` usando os mesmos parâmetros.
