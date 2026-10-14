import test from 'node:test';
import assert from 'node:assert/strict';

test('analysis survives checklist outages and retains deferred AI blockers', async (t) => {
  const head = 'a'.repeat(40);
  const keys = ['GH_TOKEN', 'GITHUB_REPOSITORY', 'PR_NUMBER', 'REVIEW_BOT_LOGIN', 'REVIEW_EXPECTED_HEAD',
    'AI_REVIEW_ENABLED', 'AI_REVIEW_MAX_ROUNDS'];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  Object.assign(process.env, { GH_TOKEN: 'test-only-placeholder', GITHUB_REPOSITORY: 'o/r', PR_NUMBER: '1',
    REVIEW_BOT_LOGIN: 'review[bot]', REVIEW_EXPECTED_HEAD: head, AI_REVIEW_ENABLED: 'true', AI_REVIEW_MAX_ROUNDS: '0' });
  t.after(() => { for (const [key, value] of Object.entries(saved)) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  } });
  let failure;
  let priorBlocker;
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    const path = new URL(url).pathname;
    let data;
    if (path === '/graphql') {
      const { query } = JSON.parse(options.body);
      if (query.includes('reviewThreads')) data = { repository: { pullRequest: {
        reviewThreads: { nodes: [], pageInfo: { hasNextPage: false } },
      } } };
      else if (query.includes('branchProtectionRules')) data = { repository: { branchProtectionRules: {
        nodes: [{ pattern: 'main', requiresStatusChecks: true, requiredStatusCheckContexts: ['test'] }],
      } } };
      else data = { repository: { pullRequest: { baseRefName: 'main', headRefOid: head,
        commits: { nodes: [{ commit: { statusCheckRollup: { contexts: {
          nodes: [{ __typename: 'CheckRun', name: 'test', status: 'COMPLETED', conclusion: 'SUCCESS' }],
        } } } }] },
      } } };
      return Response.json({ data });
    }
    if (path === '/repos/o/r/pulls/1') data = {
      state: 'open', head: { sha: head }, base: { sha: 'b'.repeat(40) }, user: { login: 'o' }, labels: [],
    };
    else if (path.endsWith('/files')) data = [];
    else if (path.endsWith('/reviews')) data = priorBlocker ? [{
      user: { login: 'review[bot]' }, state: 'CHANGES_REQUESTED',
      body: '<!-- auto-pr-review --> <!-- auto-pr-review:llm --> <!-- auto-pr-review:llm:blocking -->',
    }] : [];
    else if (path === '/repos/o/r/issues/1/comments') {
      if (failure === 'api') return new Response('Checklist API unavailable', { status: 503 });
      data = [1, 2].map((id) => ({ id, user: { login: 'review[bot]' }, body: '<!-- gfrm-required-tests -->' }));
    } else throw new Error(`Unexpected API request: ${path}`);
    return Response.json(data);
  });
  // Import only after installing the mock and environment; no GitHub or model calls leave this test process.
  const { runReview } = await import('./review-pr.mjs');
  for (failure of ['api', 'duplicate']) {
    for (priorBlocker of [false, true]) {
      const result = await runReview();
      assert.equal(result.head_sha, head);
      assert.equal(result.verdict, priorBlocker ? 'request_changes' : 'approve');
      assert.equal(result.error, undefined);
      assert.equal(result.findings.some((finding) => finding.rule === 'llm_review_pending'), priorBlocker);
    }
  }
});
