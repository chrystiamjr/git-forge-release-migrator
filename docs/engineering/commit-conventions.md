# Commit Conventions

All commits in this repository must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## Required Format

```text
<type>(<scope>): <short imperative summary>

- Bullet describing what changed and why
- One bullet per logical concern
```

Rules:

1. Scope is required for every commit subject.
2. Subject lines must be 72 characters or fewer.
3. Use imperative mood: `add`, `fix`, `refactor`, not `added` or `fixes`.
4. Bullets explain what changed and why, not implementation detail.
5. Do not add punctuation at the end of the subject line.
6. Do not add co-author trailers unless explicitly requested.

## Supported Types

| Type | Use case | Release impact |
|------|----------|----------------|
| `feat` | New capability or visible behavior | minor |
| `fix` | Bug fix or behavior correction | patch |
| `perf` | Performance improvement | patch |
| `refactor` | Internal restructuring without behavior change | patch |
| `test` | Tests only | patch |
| `chore` | Tooling or housekeeping | patch |
| `build` | Build system or compilation changes | patch |
| `style` | Formatting only | patch |
| `docs` | Documentation only | none |
| `ci` | Workflow or pipeline only | none |

## Supported Scopes

| Scope | Covers |
|-------|--------|
| `dart` | Dart production source |
| `ci` | GitHub Actions and quality gates |
| `docs` | Markdown docs, AGENTS, CHANGELOG |
| `website` | Docusaurus site code and i18n |
| `deps` | Dependency updates |
| `release` | Semantic-release and versioning |

## Examples

```text
feat(dart): add structured preflight checks

- Add shared preflight contracts so CLI and future GUI can inspect readiness
- Block runs before migration starts when fatal startup validation fails
```

```text
docs(docs): slim down AGENTS quick-start guidance

- Move procedural runbooks into engineering docs so AGENTS stays high-signal
```

