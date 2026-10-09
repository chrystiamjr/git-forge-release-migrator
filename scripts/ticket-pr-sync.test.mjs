import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { activeHumanDecision, canComplete, issueFromBody, nextState } from './ticket-pr-policy.mjs';
import { syncTicket, upsertAssociation } from './ticket-pr-sync.mjs';
import { createApi, githubList, trackerComments } from './ticket-pr-api.mjs';

const config = JSON.parse(await readFile(new URL('../.github/ticket-delivery.json', import.meta.url), 'utf8'));
const head = 'a'.repeat(40);
function pull() {
  return { number: 68, body: `YouTrack: https://${config.youtrackHost}/issue/GFRM-23`, html_url: `https://github.com/${config.repository}/pull/68`, state: 'open', merged: false, user: { login: 'chrystiamjr' }, base: { ref: 'main', repo: { full_name: config.repository } }, head: { sha: head, ref: 'feat/progress', repo: { full_name: config.repository } } };
}
function decision(body = `/reviewed ${head}`) {
  return { id: 1, body, user: { type: 'User', login: 'chrystiamjr' }, author_association: 'OWNER', created_at: '2026-10-08T12:00:00Z', updated_at: '2026-10-08T12:00:00Z', html_url: 'https://github.com/example/review' };
}
function fixture(current = 'Review') {
  const p = pull();
  const comments = [];
  const calls = [];
  const api = {
    async gh(path) {
      if (path === '/graphql') return { data: { repository: { pullRequest: { reviewThreads: { nodes: [], pageInfo: { hasNextPage: false } } } } } };
      if (path.includes('/check-runs')) return { check_runs: config.requiredChecks.map((name) => ({ name, status: 'completed', conclusion: 'success', app: { slug: 'github-actions' } })) };
      if (path.endsWith('/pulls/68')) return structuredClone(p);
      return [];
    },
    async yt(path, method, body) {
      calls.push({ path, method, body });
      if (path.startsWith('/api/users/me')) return { id: 'admin' };
      if (path.startsWith('/api/commands')) { current = body.query.split(' ').at(-1); return {}; }
      if (path.includes('/comments')) {
        if (method === 'POST') {
          const old = comments.find((item) => path.endsWith(`/${item.id}`));
          if (old) old.text = body.text;
          else comments.push({ id: `7-${comments.length}`, author: { id: 'admin' }, text: body.text });
          return {};
        }
        return comments;
      }
      return { customFields: [{ name: config.stateField, value: { name: current } }] };
    },
  };
  return { api, p, comments, calls, state: () => current };
}

test('ticket parsing rejects ambiguity, wrong host/project and supports explicit standalone plans', () => {
  assert.equal(issueFromBody(pull().body, config), 'GFRM-23');
  assert.equal(issueFromBody('Process plan: LOCAL-delivery-contract', config), null);
  assert.throws(() => issueFromBody('', config));
  assert.throws(() => issueFromBody('https://evil.test/issue/GFRM-23', config));
  assert.throws(() => issueFromBody(`https://${config.youtrackHost}/issue/OTHER-23`, config));
  assert.throws(() => issueFromBody(pull().body + `\nhttps://${config.youtrackHost}/issue/GFRM-24`, config));
});

test('human attestation excludes bots, unauthorized users, stale SHA and edited/revoked records', () => {
  assert.ok(activeHumanDecision([decision()], head, config.humanReviewers));
  assert.equal(activeHumanDecision([decision()], 'b'.repeat(40), config.humanReviewers), null);
  assert.equal(activeHumanDecision([{ ...decision(), user: { login: 'chrystiamjr', type: 'Bot' } }], head, config.humanReviewers), null);
  assert.equal(activeHumanDecision([{ ...decision(), user: { login: 'other', type: 'User' } }], head, config.humanReviewers), null);
  assert.equal(activeHumanDecision([{ ...decision(), updated_at: '2026-10-08T13:00:00Z' }], head, config.humanReviewers), null);
  const revoke = { ...decision(`/revoke-review ${head}`), id: 2, created_at: '2026-10-08T13:00:00Z', updated_at: '2026-10-08T13:00:00Z' };
  assert.equal(activeHumanDecision([decision(), revoke], head, config.humanReviewers), null);
  assert.equal(activeHumanDecision([], head, config.humanReviewers), null);
});

test('completion requires actual authorized human merge, current human evidence and all successful checks', () => {
  const p = { ...pull(), merged: true, merged_at: '2026-10-08T14:00:00Z', merge_commit_sha: 'b'.repeat(40), merged_by: { login: 'chrystiamjr', type: 'User' } };
  const human = activeHumanDecision([decision()], head, config.humanReviewers);
  const checks = [...config.requiredChecks.map((name) => ({ name, passed: true })), { name: 'resolved-conversations', passed: true }];
  assert.equal(canComplete(p, human, checks, config), true);
  for (const change of [{ merged: false }, { merge_commit_sha: null }, { base: { ref: 'other' } }, { merged_by: { login: 'bot', type: 'Bot' } }]) {
    assert.equal(canComplete({ ...p, ...change }, human, checks, config), false);
  }
  assert.equal(canComplete(p, { ...human, reviewed_at: '2026-10-08T15:00:00Z' }, checks, config), false);
  assert.equal(canComplete(p, null, checks, config), false);
  assert.equal(canComplete(p, human, [], config), false);
  assert.equal(canComplete(p, human, [...checks, { name: 'test', passed: false }], config), false);
  assert.equal(canComplete(p, human, checks.map((check) => ({ ...check, passed: false })), config), false);
});

test('association is written in existing Review and retries do not duplicate it', async () => {
  const f = fixture();
  const options = { action: 'review', number: 68, apply: true, enabled: true };
  const first = await syncTicket(f.api, config, options);
  assert.equal(first.state.status, 'already');
  assert.match(f.comments[0].text, /https:\/\/github.com\/chrystiamjr\/git-forge-release-migrator\/pull\/68/);
  await syncTicket(f.api, config, options);
  assert.equal(f.comments.length, 1);
  assert.equal(f.calls.filter((call) => call.method === 'POST').length, 1);
});

test('skipped backward/manual state still links the PR; disabled sync performs no writes', async () => {
  const f = fixture('Done');
  const result = await syncTicket(f.api, config, { action: 'review', number: 68, apply: true, enabled: true });
  assert.equal(result.state.status, 'skipped');
  assert.equal(f.comments.length, 1);
  assert.equal(f.state(), 'Done');
  const dry = fixture();
  await syncTicket(dry.api, config, { action: 'review', number: 68, apply: true });
  assert.equal(dry.calls.length, 0);
  assert.equal(nextState('Blocked', 'Done', config).status, 'skipped');
});

test('wrong repository and link marker collision stop before overwriting data', async () => {
  const f = fixture();
  f.p.base.repo.full_name = 'evil/repo';
  await assert.rejects(syncTicket(f.api, config, { action: 'review', number: 68, apply: true, enabled: true }));
  const collision = fixture();
  collision.comments.push({ id: 'other', text: `gfrm-pr-link:${config.repository}:68\n`, author: { id: 'someone-else' } });
  await assert.rejects(upsertAssociation(collision.api, collision.p, 'GFRM-23', 'replacement'));
  assert.equal(collision.comments[0].text, `gfrm-pr-link:${config.repository}:68\n`);
});

test('state changes and comment writes require successful read-back', async () => {
  const f = fixture('Develop');
  await syncTicket(f.api, config, { action: 'review', number: 68, apply: true, enabled: true });
  assert.equal(f.state(), 'Review');
  const broken = fixture();
  const original = broken.api.yt;
  broken.api.yt = (path, method, body) => method === 'POST' ? Promise.resolve({}) : original(path, method, body);
  await assert.rejects(syncTicket(broken.api, config, { action: 'link', number: 68, apply: true, enabled: true }), /not verified/);
});

test('collection helpers paginate both GitHub and YouTrack', async () => {
  const rows = Array.from({ length: 100 }, (_, id) => ({ id }));
  assert.equal((await githubList({ gh: async (path) => new URL(path, 'https://api.github.com').searchParams.get('page') === '1' ? rows : [{ id: 101 }] }, '/repos/x/y/issues/1/comments')).length, 101);
  assert.equal((await trackerComments({ yt: async (path) => path.includes('$skip=0') ? rows : [] }, 'GFRM-23')).length, 100);
});

test('HTTP failures expose status only, reject redirects and never include credentials', async () => {
  for (const status of [401, 403, 404, 429]) {
    const api = createApi(config, { GH_TOKEN: 'private-token' }, async (_url, options) => {
      assert.equal(options.redirect, 'error');
      return { ok: false, status };
    });
    await assert.rejects(api.gh('/repos/x/y/pulls/1'), new RegExp(`\\(${status}\\)`));
  }
  await assert.rejects(createApi(config, {}, async () => {}).gh('/repos/x/y/pulls/1'), /credential/);
  assert.throws(() => createApi(config).yt('/api/issues/OTHER-23'));
});

test('fork cloud metadata cannot mutate tracker even with a trusted-looking ticket URL', async () => {
  const f = fixture(); f.p.head.repo.full_name = 'attacker/fork';
  await assert.rejects(syncTicket(f.api, config, { action: 'review', number: 68, apply: true, enabled: true }), /same-repository/);
  assert.equal(f.calls.length, 0);
});

test('verified merged delivery writes Done once after pre-merge human evidence; open PR never does', async () => {
  const f = fixture();
  f.p.merged = true; f.p.state = 'closed'; f.p.merged_at = '2026-10-08T14:00:00Z';
  f.p.merge_commit_sha = 'b'.repeat(40); f.p.merged_by = { login: 'chrystiamjr', type: 'User' };
  const original = f.api.gh;
  f.api.gh = (path, ...args) => path.includes('/issues/68/comments') ? Promise.resolve([decision()]) : original(path, ...args);
  const options = { action: 'merge', number: 68, apply: true, enabled: true };
  assert.equal((await syncTicket(f.api, config, options)).complete, true);
  assert.equal(f.state(), 'Done');
  assert.match(f.comments[0].text, /canonical state verified/);
  await syncTicket(f.api, config, options);
  assert.equal(f.calls.filter((call) => call.path === '/api/commands').length, 1);
  const open = fixture();
  assert.equal((await syncTicket(open.api, config, options)).complete, false);
  assert.equal(open.state(), 'Review');
});
