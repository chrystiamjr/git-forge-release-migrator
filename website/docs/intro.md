---
sidebar_position: 1
title: Overview
hide_table_of_contents: true
---

<div className="hero-panel">
  <p className="kicker">Public docs</p>
  <h1>Move tags, releases, notes, and assets across Git forges without redoing work.</h1>
  <p>
    <code>gfrm</code> is a resilient cross-forge CLI for GitHub, GitLab, and Bitbucket Cloud. It migrates tags first,
    then releases, keeps checkpoint state on disk, and resumes interrupted runs with <code>gfrm resume</code>.
  </p>

  <div className="hero-grid">
    <div className="hero-card">
      <h3>Download compiled binaries</h3>
      <p>Use the release artifacts on clean machines. No Dart, Node, FVM, or Yarn is required on the target host.</p>
    </div>
    <div className="hero-card">
      <h3>Persist state safely</h3>
      <p>Every run writes logs, summary, and failed tags under a timestamped work directory.</p>
    </div>
    <div className="hero-card">
      <h3>Resume instead of restarting</h3>
      <p>Completed work is skipped. Incomplete or failed items are retried from saved session state.</p>
    </div>
  </div>
</div>

## Start here

<div className="section-grid">
  <div className="section-card">
    <h3><a href="./getting-started/quick-start">Quick Start</a></h3>
    <p>Choose the right release artifact, configure tokens once, and run a first migration.</p>
  </div>
  <div className="section-card">
    <h3><a href="./configuration/settings-profiles">Settings Profiles</a></h3>
    <p>Use persistent provider profiles instead of passing tokens on every run.</p>
  </div>
  <div className="section-card">
    <h3><a href="./reference/support-matrix">Support Matrix</a></h3>
    <p>Check supported cross-forge pairs, provider aliases, and explicit non-goals.</p>
  </div>
</div>

## Operating model

- Tags are migrated before releases.
- Release selection currently targets semver tags in the form `vX.Y.Z`.
- Each run writes under `./migration-results/<timestamp>/`.
- `summary.json` uses schema version `2` and includes the executed command metadata.
- When failures exist, `summary.json` includes a retry command that uses `gfrm resume`.

## Release artifacts

Download binaries and checksums from [GitHub Releases](https://github.com/chrystiamjr/git-forge-release-migrator/releases).

| Asset | Platform |
| --- | --- |
| `gfrm-macos-intel.zip` | macOS Intel |
| `gfrm-macos-silicon.zip` | macOS Apple Silicon |
| `gfrm-linux.zip` | Linux |
| `gfrm-windows.zip` | Windows |
| `checksums-sha256.txt` | SHA256 checksums for all zip assets |

## Read next

- [Install and Verify guide](/getting-started/install-and-verify)
- [First Migration](/getting-started/first-migration)
- [Bitbucket Behavior](/guides/bitbucket-behavior)
