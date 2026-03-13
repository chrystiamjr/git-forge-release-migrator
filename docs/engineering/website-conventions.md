# Website Conventions

The `website/` directory is a Docusaurus 3 site with EN and PT-BR locales.

## Source of Truth

- `website/` is the source of truth for public documentation.
- Update EN and PT-BR together when content changes.
- Run `yarn docs:build` before merging website changes.

## Key Paths

| Path | Purpose |
|------|---------|
| `website/src/pages/index.tsx` | Landing page |
| `website/src/components/DownloadSection/` | Latest release fetch and download cards |
| `website/src/components/LocaleSwitcher/` | Inline and floating locale switchers |
| `website/src/theme/Root.tsx` | Swizzled root for floating locale switcher |
| `website/src/theme/Navbar/Logo/` | Swizzled inline SVG logo |
| `website/src/css/custom.css` | Global CSS variables and layout styling |
| `website/i18n/pt-BR/` | PT-BR translations and Docusaurus locale files |

## i18n Rules

- Wrap all user-visible React strings with `<Translate>` or `translate({id, message})`.
- Translation keys should follow `<area>.<component>.<description>`.
- Do not add EN keys without PT-BR translations.
- `scripts/check-translations.mjs` validates required translation keys and non-empty values.

## Local Checks

Relevant scripts:

- `scripts/check-translations.mjs`
- `scripts/validate-commit-msg.mjs`
- `yarn docs:build`
- `yarn test:website`

Husky hooks:

- `pre-commit`: Dart format/analyze and translation checks when website files are staged
- `commit-msg`: Conventional Commit validation
- `pre-push`: Dart tests and commit message validation for pushed commits

## Important UI Note

`website/src/theme/Navbar/Logo/index.tsx` exists to avoid the Docusaurus dual-image flash during SSR and hydration by rendering one inline SVG that follows `var(--ifm-color-primary)`.

