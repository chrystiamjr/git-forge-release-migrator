# Task

Add desktop build and release automation for the GUI.

## Intent

Make GUI packaging repeatable and testable across Windows, macOS, and Linux so desktop delivery becomes a managed
release concern rather than a manual developer task.

## Detailed scope

- Add desktop GUI build jobs for:
  - Windows
  - macOS
  - Linux
- Preserve existing CLI release expectations while extending automation for GUI outputs.
- Keep macOS validation aligned with existing Intel and Apple Silicon requirements where relevant.
- Add post-build smoke checks for startup and minimal navigation.
- Define how GUI artifacts fit into release validation without bypassing current quality gates.

## Expected changes

- CI or release automation can build GUI artifacts reproducibly for supported desktop targets.
- GUI packaging is validated by smoke checks before release publication.
- Desktop build automation becomes explicit and maintainable instead of tribal workflow knowledge.
- Existing CLI release behavior remains intact while GUI distribution is added alongside it.

## Non-goals and guardrails

- Do not bypass Dart quality gates to accelerate GUI packaging.
- Do not change documented macOS release expectations without updating repository guidance.
- Do not make GUI builds the only release path while CLI remains a supported interface.
- Do not ship unverified GUI artifacts.

## Test and validation

- Add build-pipeline checks for each supported desktop target.
- Add smoke tests proving the packaged application starts and reaches minimal navigation.
- Verify GUI packaging does not regress current CLI release behavior.
- Validate macOS architecture expectations where applicable.
- Run `yarn lint:dart`, `yarn test:dart`, and `yarn coverage:dart` as part of the release-quality baseline.

## Exit criteria

- GUI desktop artifacts can be built repeatably for supported targets.
- Post-build smoke validation exists.
- GUI release automation coexists with existing CLI release expectations.
- The project can produce validated GUI artifacts without manual, undocumented steps.
