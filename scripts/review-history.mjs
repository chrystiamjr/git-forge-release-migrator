import { createHash } from 'node:crypto';
import { githubGraphql } from './github-api.mjs';

export const FINDING_MARKER = 'gfrm-finding';
const BLOCKING = new Set(['critical', 'bug', 'important', 'blocking']);

export function findingId(finding) {
  if (finding.finding_id) return finding.finding_id;
  const identity = [finding.rule, finding.path, finding.symbol, finding.concern || finding.message];
  return `f-${createHash('sha256').update(JSON.stringify(identity)).digest('hex').slice(0, 24)}`;
}

export function findingMetadata(body) {
  const match = String(body).match(/<!-- gfrm-finding:(\{[^\n]+\}) -->/);
  try { return match ? JSON.parse(match[1]) : null; } catch { return null; }
}

export function findingMarker(finding, state = 'applicable') {
  const metadata = JSON.stringify({ id: findingId(finding), state, tier: finding.tier, message: finding.message })
    .replaceAll('<', '\\u003c').replaceAll('>', '\\u003e');
  return `<!-- ${FINDING_MARKER}:${metadata} -->`;
}

export function priorFinding(comment) {
  const metadata = findingMetadata(comment.body);
  return {
    finding_id: metadata?.id || `legacy-${comment.id}`,
    tier: metadata?.tier || String(comment.body).match(/\[(critical|bug|important|suggestion|question|blocking|note)\]/)?.[1] || 'important',
  };
}

// Both thread and comment connections are paginated: an old resolved thread can still contain useful evidence.
export async function fetchReviewHistory(owner, repo, number, botLogin, trustedAuthors, graphql = githubGraphql) {
  if (!botLogin) throw new Error('Review bot identity is required to load trusted history');
  const threads = [];
  let cursor = null;
  do {
    const data = await graphql(`query($owner:String!,$repo:String!,$number:Int!,$cursor:String) {
      repository(owner:$owner,name:$repo) { pullRequest(number:$number) {
        reviewThreads(first:100,after:$cursor) { pageInfo { hasNextPage endCursor } nodes {
          id isResolved isOutdated path line originalLine
          comments(first:100) { pageInfo { hasNextPage endCursor } nodes {
            databaseId body url author { login } replyTo { databaseId }
          } }
        } }
      } }
    }`, { owner, repo, number, cursor });
    const connection = data.repository.pullRequest.reviewThreads;
    threads.push(...connection.nodes);
    cursor = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null;
  } while (cursor);
  const history = [];
  for (const thread of threads) {
    const comments = [...thread.comments.nodes];
    let page = thread.comments.pageInfo;
    while (page.hasNextPage) {
      const data = await graphql(`query($id:ID!,$cursor:String) { node(id:$id) {
        ... on PullRequestReviewThread { comments(first:100,after:$cursor) {
          pageInfo { hasNextPage endCursor } nodes { databaseId body url author { login } replyTo { databaseId } }
        } }
      } }`, { id: thread.id, cursor: page.endCursor });
      comments.push(...data.node.comments.nodes);
      page = data.node.comments.pageInfo;
    }
    const root = comments[0];
    if (root?.author?.login !== botLogin || !root.body.includes('<!-- auto-pr-review -->')) continue;
    const updates = comments.filter((comment) => comment.author?.login === botLogin && findingMetadata(comment.body));
    const latest = updates.at(-1) || root;
    history.push({
      ...priorFinding({ id: root.databaseId, body: root.body }),
      tier: findingMetadata(latest.body)?.tier || priorFinding({ id: root.databaseId, body: root.body }).tier,
      comment_id: root.databaseId, thread_id: thread.id, url: root.url,
      path: thread.path, line: thread.line, original_line: thread.originalLine,
      resolved: thread.isResolved, outdated: thread.isOutdated,
      state: findingMetadata(latest.body)?.state || 'applicable',
      body: root.body, latest_body: latest.body,
      replies: comments.slice(1).filter((comment) => trustedAuthors.includes(comment.author?.login))
        .map((comment) => ({ author: comment.author.login, body: comment.body, url: comment.url })),
    });
  }
  return history;
}

export function reconcileFindings(findings, assessments, history) {
  const byId = new Map(history.map((item) => [item.finding_id, item]));
  const decisions = new Map();
  for (const assessment of assessments || []) {
    if (!byId.has(assessment.finding_id) || decisions.has(assessment.finding_id)) {
      throw new Error('Invalid or duplicate prior-finding assessment');
    }
    if (!['applicable', 'fixed', 'answered', 'uncertain'].includes(assessment.state) || !assessment.reason?.trim()) {
      throw new Error('Prior-finding assessment needs a state and evidence');
    }
    decisions.set(assessment.finding_id, assessment);
  }
  const result = [];
  for (const finding of findings) {
    const previousId = finding.previous_finding_id;
    if (previousId && !byId.has(previousId)) throw new Error('Finding references unknown history');
    const decision = decisions.get(previousId);
    if (decision && ['fixed', 'answered'].includes(decision.state)) throw new Error('Contradictory finding assessment');
    result.push({ ...finding, finding_id: previousId || findingId(finding) });
  }
  for (const prior of history) {
    const decision = decisions.get(prior.finding_id);
    if (decision && ['fixed', 'answered'].includes(decision.state)) continue;
    if (result.some((finding) => finding.finding_id === prior.finding_id)) continue;
    // Verified bot closure survives omission; a new finding or explicit assessment can reopen it.
    if (!decision && ['fixed', 'answered'].includes(prior.state)) continue;
    // Omitted/uncertain assessments cannot silently clear an outstanding blocker, even on resolved threads.
    if (BLOCKING.has(prior.tier)) result.push({
      finding_id: prior.finding_id, rule: 'prior_finding_pending', tier: prior.tier,
      severity: 'blocking', path: prior.path, line: prior.line, inline: false,
      message: decision?.reason || 'Previous blocking finding has not been verified against the current code.',
      existing_url: prior.url,
    });
  }
  return [...new Map(result.map((finding) => [finding.finding_id, finding])).values()];
}
