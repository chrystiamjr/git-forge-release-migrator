# Task

Finalize documentation and operational readiness for dual-interface releases.

## Intent

Ensure public and developer-facing guidance explains how CLI and GUI coexist, how users troubleshoot each path, and
what operational guarantees still come from the shared runtime.

## Detailed scope

- Publish GUI usage documentation, troubleshooting guidance, and release notes support for the docs site.
- Keep `README.md` and `dart_cli/README.md` concise and aligned with the documentation source of truth.
- Ensure documentation explains that CLI remains supported in parallel with the GUI.
- Document secure credential behavior, retry semantics, artifact handling, and major GUI operational flows.
- Ensure localization or translation work is scheduled appropriately after the source documentation stabilizes.

## Expected changes

- Public docs describe the GUI without implying CLI deprecation.
- Developer docs explain the shared runtime boundaries and operational expectations for both interfaces.
- Troubleshooting guidance exists for GUI startup, credential storage, retry, and artifact access.
- Release communication for GUI-enabled versions becomes clearer and more consistent.

## Non-goals and guardrails

- Do not let GUI docs contradict the CLI contract.
- Do not let README files drift into long-form product manuals.
- Do not publish release guidance that hides current limitations or degraded modes.
- Do not treat translation as complete before the source documentation is stable.

## Test and validation

- Review all dual-interface documentation for consistency with `AGENTS.md` and runtime contracts.
- Validate links and editorial coherence across public and developer docs.
- Confirm GUI docs match actual implemented flows and current limitations.
- If the material is integrated into the public docs site, run `yarn docs:build`.

## Exit criteria

- GUI and CLI coexistence is documented clearly.
- Operational guidance is consistent with actual runtime behavior.
- Public and developer docs are ready to support GUI-enabled releases.
- Documentation no longer depends on implicit team knowledge for core GUI workflows.
