# Git Forge Release Migrator (gfrm)

[![License](https://img.shields.io/badge/license-MIT-green)](docs/LICENSE)
[![Release](https://img.shields.io/badge/release-semantic--release-informational)](./release.config.cjs)
[![Flutter SDK](https://img.shields.io/badge/Flutter%20SDK-3.41.0-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart SDK](https://img.shields.io/badge/Dart%20SDK-3.11.0-0175C2?logo=dart&logoColor=white)](https://dart.dev/)

`gfrm` is a resilient cross-forge CLI that migrates **tags, releases, notes, and assets** across GitHub, GitLab, and
Bitbucket with idempotent retries.

## How it Works

`gfrm` migrates **tags first**, then **releases** (idempotent, checkpoint-based). Each run writes a timestamped artifact
directory with a log, a summary, and a list of failed tags. Interrupted runs can be resumed with `gfrm resume` —
completed items are skipped automatically.

## Quick Start

1. Download the artifact for your OS from the [releases page](../../releases).
2. Unzip and make executable (macOS/Linux: `chmod +x ./gfrm`).
3. Bootstrap your settings once:
   ```bash
   ./gfrm setup
   ```
4. Run your first migration:
   ```bash
   ./gfrm migrate \
     --source-provider gitlab \
     --source-url "https://gitlab.com/group/project" \
     --target-provider github \
     --target-url "https://github.com/org/repo"
   ```
5. If the run is interrupted, resume with:
   ```bash
   ./gfrm resume
   ```

## Documentation

For usage details and documentation in other languages, use the docs under [/docs](docs) with your desired language
folder.

- English docs: [docs/en_us](docs/en_us)
- Portuguese docs: [docs/pt_br](docs/pt_br)
- Development/runtime guide: [dart_cli/README.md](dart_cli/README.md)

> The Dart SDK is managed via [FVM](https://fvm.app/) (`3.41.0` / Dart `3.11.0`). FVM also sets the stage for an
> upcoming Flutter UI application.

## Support Matrix

Supported cross-forge pairs:

- `gitlab -> github`
- `github -> gitlab`
- `github -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> github` (Bitbucket Cloud)
- `gitlab -> bitbucket` (Bitbucket Cloud)
- `bitbucket -> gitlab` (Bitbucket Cloud)

Not supported in this phase:

- same-provider migrations (`github->github`, `gitlab->gitlab`, `bitbucket->bitbucket`)
- Bitbucket Data Center / Server

## Running The Compiled CLI

Release assets:

- `gfrm-macos-intel.zip`
- `gfrm-macos-silicon.zip`
- `gfrm-linux.zip`
- `gfrm-windows.zip`
- `checksums-sha256.txt` — SHA256 checksums for all zip artifacts

`gfrm` compiled binaries run on clean machines without Dart/FVM/Node/Yarn.

To verify integrity before running:

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

Notes:

- macOS: choose `intel` or `silicon` artifact based on machine type.
- macOS troubleshooting fallback: `xattr -d com.apple.quarantine ./gfrm`.
- In `MACOS_RELEASE_SECURITY_MODE=strict`, release jobs fail when signing/notarization is not completed.

## Command Overview

- `gfrm migrate`: starts a migration from explicit source/target arguments
- `gfrm resume`: resumes from saved session state
- `gfrm demo`: local simulation flow
- `gfrm setup`: interactive bootstrap for settings profile
- `gfrm settings`: token/profile settings management

## Settings Profiles

Settings commands:

```bash
gfrm settings init [--profile <name>] [--local] [--yes]
gfrm settings set-token-env --provider <github|gitlab|bitbucket> --env-name <ENV_NAME> [--profile <name>] [--local]
gfrm settings set-token-plain --provider <github|gitlab|bitbucket> [--token <value>] [--profile <name>] [--local]
gfrm settings unset-token --provider <github|gitlab|bitbucket> [--profile <name>] [--local]
gfrm settings show [--profile <name>]
```

Settings files:

- global: `~/.config/gfrm/settings.yaml` (or `XDG_CONFIG_HOME/gfrm/settings.yaml`)
- local override: `./.gfrm/settings.yaml`

Profile resolution order:

1. explicit `--settings-profile`
2. `defaults.profile` in settings
3. `default`

Default token resolution order:

1. `migrate`: settings provider token (`token_env`, then `token_plain`)
2. `migrate`: env aliases (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, provider aliases)
3. `resume`: session token context
4. `resume`: settings provider token (`token_env`, then `token_plain`)
5. `resume`: env aliases (`GFRM_SOURCE_TOKEN`, `GFRM_TARGET_TOKEN`, provider aliases)

## Migration Examples

Bootstrap settings when starting from zero:

```bash
gfrm setup
```

Run migration with configured settings profile:

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

Dry-run (validate and simulate without writing to the target):

```bash
gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo" \
  --dry-run
```

Resume from session (default file is `./sessions/last-session.json` when omitted):

```bash
gfrm resume --session-file ./sessions/last-session.json
```

## Artifacts and Retry

Each run writes under:

```text
./migration-results/<YYYYMMDD-HHMMSS>/
```

Artifacts:

- `migration-log.jsonl`
- `summary.json` (schema v2, includes `schema_version` and executed command)
- `failed-tags.txt`

When failures exist, `summary.json` includes `retry_command` using `gfrm resume`.

## Diagnostic Warnings

`gfrm` writes warnings to `stderr` in two situations without interrupting the migration:

- **Corrupt checkpoint entry** — if a `.jsonl` checkpoint line cannot be parsed, a warning is printed and that entry is skipped. Remaining entries are still loaded.
- **Malformed settings file** — if a `settings.yaml` file fails YAML parsing, `gfrm` retries as JSON and warns. If both fail, defaults are used.

In both cases the warning format is:

```
[gfrm] warning: <description>
```

## Exit Codes

- `0`: successful run (all items migrated or previously completed)
- non-zero: validation or operational failure (check `summary.json` and `failed-tags.txt`)
