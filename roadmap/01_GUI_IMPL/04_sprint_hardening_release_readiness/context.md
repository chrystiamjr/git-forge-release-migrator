# Goal

Harden the dual-interface product so the future GUI can ship alongside the CLI in stable v0.x releases without
compromising security, parity, release repeatability, or documentation clarity.

## Why this sprint exists now

After the GUI foundation exists, the remaining work is operational rather than foundational. The product must gain
secure credential handling, repeatable desktop packaging, explicit CLI/GUI parity checks, and clear public guidance
before it can be treated as release-ready.

## Dependencies and entry criteria

- Sprint 3 GUI flows must already work in controlled desktop scenarios.
- Existing CLI release pipelines must remain green throughout this sprint.
- Security defaults must continue to prohibit raw token logging.
- Existing artifact and summary contracts must remain unchanged.
- GUI release readiness must be evaluated against CLI behavior, not independently from it.

## Tasks in this sprint

- `task01_secure_credential_storage_per_os.md`
- `task02_desktop_build_and_release_automation.md`
- `task03_cli_gui_parity_validation.md`
- `task04_documentation_and_operational_readiness.md`
