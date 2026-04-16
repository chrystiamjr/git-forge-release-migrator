---
sidebar_position: 1
title: Visão Geral
hide_table_of_contents: true
---

<div className="hero-panel">
  <p className="kicker">Documentação pública</p>
  <h1>Migre tags, releases, notas e artefatos entre Git forges sem refazer trabalho.</h1>
  <p>
    <code>gfrm</code> é uma CLI cross-forge resiliente para GitHub, GitLab e Bitbucket Cloud. Ela migra tags primeiro,
    depois releases, mantém checkpoints em disco e retoma execuções interrompidas com <code>gfrm resume</code>.
  </p>

  <div className="hero-grid">
    <div className="hero-card">
      <h3>Baixe binários compilados</h3>
      <p>Use os artefatos de release em máquinas limpas. O host de destino não precisa de Dart, Node, FVM ou Yarn.</p>
    </div>
    <div className="hero-card">
      <h3>Persista estado com segurança</h3>
      <p>Cada execução grava logs, sumário e tags com falha em um diretório versionado por timestamp.</p>
    </div>
    <div className="hero-card">
      <h3>Retome em vez de reiniciar</h3>
      <p>Itens concluídos são ignorados. Itens incompletos ou com falha são retomados a partir da sessão salva.</p>
    </div>
  </div>
</div>

## Comece por aqui

<div className="section-grid">
  <div className="section-card">
    <h3><a href="./getting-started/quick-start">Início Rápido</a></h3>
    <p>Escolha o artefato correto, configure tokens uma vez e execute a primeira migração.</p>
  </div>
  <div className="section-card">
    <h3><a href="./configuration/settings-profiles">Perfis de Configuração</a></h3>
    <p>Use perfis persistentes de provider em vez de passar tokens em cada comando.</p>
  </div>
  <div className="section-card">
    <h3><a href="./reference/support-matrix">Matriz de Suporte</a></h3>
    <p>Consulte pares cross-forge suportados, aliases de provider e os não-objetivos explícitos.</p>
  </div>
</div>

## Modelo operacional

- Tags são migradas antes de releases.
- A seleção de releases atualmente mira tags semver no formato `vX.Y.Z`.
- Cada execução grava em `./migration-results/<timestamp>/`.
- `summary.json` usa schema version `2` e inclui metadados do comando executado.
- Quando existem falhas, `summary.json` inclui um retry command com `gfrm resume`.

## Artefatos de release

Baixe binários e checksums em [GitHub Releases](https://github.com/chrystiamjr/git-forge-release-migrator/releases).

| Artefato | Plataforma |
| --- | --- |
| `gfrm-macos-intel.zip` | macOS Intel |
| `gfrm-macos-silicon.zip` | macOS Apple Silicon |
| `gfrm-linux.zip` | Linux |
| `gfrm-windows.zip` | Windows |
| `checksums-sha256.txt` | Checksums SHA256 de todos os zips |

## Leia em seguida

- [Instalar e Validar](/getting-started/install-and-verify)
- [Primeira Migração](/getting-started/first-migration)
- [Comportamento do Bitbucket](/guides/bitbucket-behavior)
