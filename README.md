<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="website/static/img/logo-dark.svg">
    <img alt="gfrm logo" src="website/static/img/logo.svg" height="150">
  </picture>
</p>

# Git Forge Release Migrator (gfrm)

[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Release](https://img.shields.io/badge/release-semantic--release-informational)](./release.config.cjs)
[![Flutter SDK](https://img.shields.io/badge/Flutter%20SDK-3.41.0-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart SDK](https://img.shields.io/badge/Dart%20SDK-3.11.0-0175C2?logo=dart&logoColor=white)](https://dart.dev/)

`gfrm` is a resilient cross-forge CLI that migrates **tags, releases, notes, and assets** across GitHub, GitLab, and
Bitbucket with idempotent retries.

## Documentation

Full documentation is available at **[gfrm.envolvosystems.com.br](https://gfrm.envolvosystems.com.br/)**.

- Development/runtime guide: [dart_cli/README.md](dart_cli/README.md)

## Quick Start

1. Download the artifact for your OS
   from [GitHub Releases](https://github.com/chrystiamjr/git-forge-release-migrator/releases).
2. Extract the archive and run `./gfrm --help` (or `./gfrm.exe --help` on Windows).
3. Configure tokens once with `./gfrm setup`.
4. Run a migration with explicit source and target URLs.
5. Use `./gfrm resume` if the run is interrupted.

Full install, configuration, command reference, and troubleshooting live in the public docs site.
