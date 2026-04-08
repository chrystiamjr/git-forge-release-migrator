---
sidebar_position: 1
title: Quick Start
---

Start with the compiled binary for your platform, configure provider tokens once, and run a migration with explicit
source and target URLs.

## 1. Download the right artifact

Use the release page for your platform-specific zip:

- `gfrm-macos-intel.zip`
- `gfrm-macos-silicon.zip`
- `gfrm-linux.zip`
- `gfrm-windows.zip`
- `checksums-sha256.txt`

The release page is the source of truth: [GitHub Releases](https://github.com/chrystiamjr/git-forge-release-migrator/releases).

## 2. Verify and run `--help`

Follow [Install and Verify](/getting-started/install-and-verify) to extract the artifact and confirm the binary runs.
Use `./gfrm <command> --help` when you need command-specific flags for `migrate`, `resume`, `setup`, or `settings`.

## 3. Bootstrap token settings

```bash
./gfrm setup
```

This writes provider token settings to your global config by default.

## 4. Run a first migration

```bash
./gfrm migrate \
  --source-provider gitlab \
  --source-url "https://gitlab.com/group/project" \
  --target-provider github \
  --target-url "https://github.com/org/repo"
```

## 5. Resume if interrupted

```bash
./gfrm resume
```

`gfrm` resumes from saved session state and skips work that already completed.
If a run stops before tag creation because the target forge is missing commit history for source tags, read the
remediation hints in `summary.json` before retrying.
