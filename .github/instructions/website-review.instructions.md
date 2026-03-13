---
applyTo: "website/**/*"
---

# Website Review Rules

- Wrap user-facing React strings in translation helpers and keep PT-BR translations in sync.
- For docs-site changes, validate translation keys and keep `code.json`, `current.json`, `navbar.json`, and `footer.json` consistent when applicable.
- Preserve the existing Docusaurus structure and locale behavior; avoid one-off patterns that bypass shared components or translation flow.
- If the site changes user-visible CLI behavior or product contract text, make sure the matching docs pages are updated in both locales.
- Favor clear, maintainable content and layout changes over clever front-end abstractions.
