# PR Review Playbook

Use this flow when asked to address inline review comments on an open PR.

## Automated reviewer

`scripts/review-pr.mjs` runs two layers after Quality Checks:

- **Hard rules** (secrets, contract invariants, EN/PT-BR docs sync, layer imports): deterministic `[blocking]`.
- **AI review** (`scripts/ai-review.mjs`, prompt in `scripts/ai-review-prompt.md`): reads the patch plus the full
  post-change file, `AGENTS.md`, and the matching `.github/instructions/*`. `[critical]` and `[important]` block;
  `[suggestion]` and `[question]` do not. Fuzzy heuristics (long method, `setState`, test gaps, …) are sent as hints
  that the model confirms or dismisses.

The AI layer is opt-in and owner-only: set repo variable `AI_REVIEW_ENABLED=true`; it then runs only on PRs authored
and triggered by the repository owner. PR content is untrusted prompt input, so the gate limits prompt-injection exposure and
subscription quota use. Other contributors' PRs get the hard rules plus hints; review those locally with your own
tooling. The workflow runs the review scripts from the default branch, so reviewer changes take effect after merge. Set `AI_REVIEW_ENABLED=false` (or delete it) to turn it off.

| Engine (`AI_REVIEW_ENGINE`) | Credential | Optional variables |
|---|---|---|
| `claude` (default) | secret `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token` | `CLAUDE_MODEL` (unset = routed, see below; set = pinned), `CLAUDE_EFFORT` (default `medium`, only with `CLAUDE_MODEL`) |
| `gemini` | secret `GEMINI_API_KEY` (paid quota) | `GEMINI_MODEL` (default `gemini-flash-latest`), `GEMINI_THINKING_LEVEL` (default `high`) |

Claude runs headless with all tools disabled, from an empty directory, without GitHub or Gemini credentials in its
environment. The review body records the engine, model, and resolved model version. If the engine fails, the review
fails closed with `llm_review_unavailable`; re-run the workflow.

Unless `CLAUDE_MODEL` is set, the claude engine routes each PR by tier (`scripts/ai-review-triage-prompt.md`):
docs-only PRs (`website/**`, `README.md`) go straight to `light`; otherwise a Haiku call at effort `low` reads the
patches and picks `light` (haiku, `low`), `standard` (sonnet, `medium`), or `deep` (opus, `medium`). If triage fails,
the review uses `standard`. The review footer shows the chosen tier, its reason, and the combined cost.

## 1. Fetch inline comments

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api \
  repos/<owner>/<repo>/pulls/<pr_number>/comments
```

Classify each comment before editing:

| Class | Action |
|-------|--------|
| Clear bug or correct suggestion | Fix it now |
| Style or naming preference | Apply if aligned with repo rules |
| Breaking change | Defer to follow-up |
| Pre-existing issue | Acknowledge and propose follow-up |

## 2. Apply fixes and validate

Run the standard quality gates after making applicable changes:

```bash
yarn lint:dart
yarn test:dart
yarn coverage:dart
```

## 3. Commit and push

Use one commit for the review round and push to the same branch:

```bash
git push origin <branch>
```

## 4. Reply inline to each handled comment

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api \
  repos/<owner>/<repo>/pulls/<pr_number>/comments/<comment_id>/replies \
  -f body="<reply>"
```

Reply guidelines:

- fixed comments: say what changed and in which commit
- deferred comments: explain why they are out of scope for this PR and what the follow-up is
- keep replies factual and concise

## 5. Resolve review threads

Fetch thread IDs:

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api graphql -f query='
{
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <pr_number>) {
      reviewThreads(first: 20) {
        nodes {
          id
          isResolved
          comments(first: 1) { nodes { databaseId } }
        }
      }
    }
  }
}'
```

Resolve a thread:

```bash
GH_TOKEN=${GH_PERSONAL_TOKEN:-$GH_TOKEN} gh api graphql -f query="
  mutation {
    resolveReviewThread(input: { threadId: \"<thread_id>\" }) {
      thread { id isResolved }
    }
  }"
```


## Ticket delivery

Apply [ticket delivery](ticket-delivery.md) and [testing playbook](testing-playbook.md) after fixes. New commits invalidate the previous human review decision. Bot approval is auxiliary; leave the linked ticket in Review until the human-reviewed current head is manually merged. Never impersonate the maintainer or merge through ticket-worker.
