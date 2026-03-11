# GUI Implementation Epic - Current Progress

This epic aims to evolve GFRM from a CLI-only tool into a dual-interface product with both CLI and desktop GUI.
The implementation target remains a shared Dart runtime, with the CLI contract preserved as the authority for
migration semantics, token precedence, artifacts, retry behavior, and summary compatibility.
At the moment, the repository shows planning material for this epic, but it does not yet show production
implementation of the application service layer, runtime event contracts, desktop GUI, or GUI release hardening.

## What is already done

- The repository already defines the current CLI contract, compatibility invariants, and delivery constraints in `AGENTS.md`.
- The repository already pins the Flutter/Dart toolchain through `.fvmrc`, which makes Flutter Desktop technically viable as
  a future implementation path.
- The GUI epic has already been planned and decomposed into four implementation sprints with explicit contracts and guardrails.
- The current roadmap material has now been reorganized into sprint folders and task-level documents for execution planning.
- The repository currently remains centered on the Dart CLI runtime and its existing validation, testing, and artifact rules.

## What is not implemented yet

- There is no observable GUI application code in the repository for Windows, macOS, or Linux.
- There is no observable application service layer in production code exposing `RunRequest`, `RunResult`, and `RunFailure`.
- There is no observable runtime event contract implementation exposing `RuntimeEventEnvelope` or `RunState`.
- There is no observable desktop controller boundary such as `DesktopRunController`.
- There is no observable secure GUI credential storage abstraction such as `CredentialStore`.
- There is no evidence that GUI-specific build, parity, or release-readiness flows have been implemented.
- The current state of this epic is planning and documentation, not functional delivery.

## Current progress by sprint

- Sprint 1: `0% implementation` - planning exists, but no application service or structured preflight implementation is
  observable in runtime code.
- Sprint 2: `0% implementation` - planning exists, but no runtime event envelope, ordered publisher, or `RunState`
  reducer is observable in runtime code.
- Sprint 3: `0% implementation` - planning exists, but no Flutter Desktop app, GUI screens, or GUI-to-runtime boundary
  is observable in the repository.
- Sprint 4: `0% implementation` - planning exists, but no GUI credential store, GUI release automation, or CLI/GUI parity
  validation matrix is observable in implementation code.
