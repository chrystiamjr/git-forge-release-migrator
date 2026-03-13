---
applyTo: "README.md,dart_cli/README.md,website/docs/**/*.md,website/i18n/pt-BR/docusaurus-plugin-content-docs/current/**/*.md"
---

# Documentation Review Rules

- `website/` is the public source of truth. Keep `README.md` and `dart_cli/README.md` aligned and concise.
- When public behavior changes, update both English and PT-BR docs together.
- Keep these contracts accurate:
  - semver-only release selection in `vX.Y.Z`
  - tags-first migration flow
  - `summary.json` schema version `2`
  - retry guidance based on `gfrm resume`
  - token precedence and settings-profile behavior
  - supported forge pairs and Bitbucket Cloud scope
- Do not document `--skip-tags` as a general shortcut. Explain it as a constrained compatibility option.
- If you touch docs under `website/docs/**`, ensure the corresponding PT-BR file under `website/i18n/pt-BR/docusaurus-plugin-content-docs/current/**` is updated too.
- Prefer concrete commands and expected behavior over marketing language or vague claims.
