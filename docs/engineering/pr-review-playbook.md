# PR Review Playbook

Use this flow when asked to address inline review comments on an open PR.

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

