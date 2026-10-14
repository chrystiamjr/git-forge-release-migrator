import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

async function analysisFixture(t) {
  const head = 'a'.repeat(40);
  const keys = ['GH_TOKEN', 'GITHUB_REPOSITORY', 'PR_NUMBER', 'REVIEW_BOT_LOGIN', 'REVIEW_EXPECTED_HEAD',
    'AI_REVIEW_ENABLED', 'AI_REVIEW_MAX_ROUNDS'];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  Object.assign(process.env, { GH_TOKEN: 'test-only-placeholder', GITHUB_REPOSITORY: 'o/r', PR_NUMBER: '1',
    REVIEW_BOT_LOGIN: 'review[bot]', REVIEW_EXPECTED_HEAD: head, AI_REVIEW_ENABLED: 'true', AI_REVIEW_MAX_ROUNDS: '0' });
  t.after(() => { for (const [key, value] of Object.entries(saved)) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  } });
  const state = { failure: null, priorBlocker: false, files: [] };
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
    else if (path.endsWith('/files')) data = state.files;
    else if (path.endsWith('/reviews')) data = state.priorBlocker ? [{
      user: { login: 'review[bot]' }, state: 'CHANGES_REQUESTED',
      body: '<!-- auto-pr-review --> <!-- auto-pr-review:llm --> <!-- auto-pr-review:llm:blocking -->',
    }] : [];
    else if (path === '/repos/o/r/issues/1/comments') {
      if (state.failure === 'api') return new Response('Checklist API unavailable', { status: 503 });
      data = state.failure === 'duplicate'
        ? [1, 2].map((id) => ({ id, user: { login: 'review[bot]' }, body: '<!-- gfrm-required-tests -->' })) : [];
    } else throw new Error(`Unexpected API request: ${path}`);
    return Response.json(data);
  });
  // Import only after installing the mock and environment; no GitHub or model calls leave this test process.
  const { runReview } = await import('./review-pr.mjs');
  return { runReview, state, head };
}

test('analysis survives checklist outages and retains deferred AI blockers', async (t) => {
  const { runReview, state, head } = await analysisFixture(t);
  for (state.failure of ['api', 'duplicate']) {
    for (state.priorBlocker of [false, true]) {
      const result = await runReview();
      assert.equal(result.head_sha, head);
      assert.equal(result.verdict, state.priorBlocker ? 'request_changes' : 'approve');
      assert.equal(result.error, undefined);
      assert.equal(result.findings.some((finding) => finding.rule === 'llm_review_pending'), state.priorBlocker);
    }
  }
});

test('production PR normalization reaches real snapshot preparation in shadow mode', async (t) => {
  const { runReview, state, head } = await analysisFixture(t);
  const { runAiReview } = await import('./ai-review.mjs');
  const { isolatedReview, prepareSnapshot, REVIEW_CLI_VERSION } = await import('./review-runner.mjs');
  process.env.AI_REVIEW_MAX_ROUNDS = '3';
  state.files = [{ filename: 'a.dart', status: 'added', patch: '@@ -0,0 +1 @@\n+bad();' }];
  const finding = { tier: 'bug', path: 'a.dart', line: 1, message: 'Broken call', why: 'Fails on use', symbol: 'bad' };
  const detected = { findings: [finding], prior_assessments: [], test_requirements: [], design_notes: [], dismissed_hints: [] };
  const output = { decisions: [{ id: 'findings:0', decision: 'substantiated', reason: 'Call exists',
    evidence: [{ path: 'a.dart', line: 1, quote: 'bad();' }] }] };
  let snapshotCalls = 0;
  const result = await runReview({ aiReviewer: (input) => runAiReview({ ...input,
    env: { AI_REVIEW_VERIFICATION_MODE: 'shadow', CLAUDE_CODE_OAUTH_TOKEN: 'test-only', CLAUDE_MODEL: 'sonnet' },
    io: { listInstructionPaths: async () => [], readRepoFile: async () => '', readChangedFile: async () => 'bad();' },
    runCommand: async () => ({ exitCode: 0, stdout: JSON.stringify({ subtype: 'success', structured_output: detected }), stderr: '' }),
    verificationRunner: (options) => isolatedReview({ ...options,
      run: async (command, args) => {
        assert.equal(command, 'claude');
        return { exitCode: 0, stdout: args[0] === '--version' ? `${REVIEW_CLI_VERSION} (Claude Code)`
          : JSON.stringify({ subtype: 'success', structured_output: output }) };
      },
      snapshot: (options) => prepareSnapshot({ ...options, run: async (command, args) => {
        snapshotCalls++;
        if (command === 'gh') {
          assert.deepEqual(args, ['api', `/repos/o/r/tarball/${head}`]);
          return { exitCode: 0, stdout: Buffer.from('mock archive') };
        }
        assert.equal(command, 'python3');
        await mkdir(args[2], { recursive: true });
        await writeFile(join(args[2], 'a.dart'), 'bad();\n');
        return { exitCode: 0 };
      } }),
    }),
  }) });
  assert.equal(snapshotCalls, 2);
  assert.equal(result.llm.verification.status, 'complete');
  assert.equal(result.head_sha, head);
});
