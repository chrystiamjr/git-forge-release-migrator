import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { captureReviewBinding, readHumanDecision, readReviewBindings } from './ticket-human-review.mjs';
import { activeHumanDecision, canComplete } from './ticket-pr-policy.mjs';
import { handleEvent } from './ticket-delivery-event.mjs';
import { syncTicket } from './ticket-pr-sync.mjs';

const config = JSON.parse(await readFile(new URL('../.github/ticket-delivery.json', import.meta.url), 'utf8'));
const head = 'a'.repeat(40);

function fixture() {
  const comment = { id: 42, body: '/reviewed', user: { type: 'User', login: 'chrystiamjr' }, author_association: 'OWNER',
    created_at: '2026-10-09T12:00:00Z', updated_at: '2026-10-09T12:00:00Z', html_url: 'https://github.com/example/comment/42',
    issue_url: `https://api.github.com/repos/${config.repository}/issues/72` };
  const pull = { number: 72, state: 'open', merged: false, body: 'Process plan: LOCAL-optional-review-sha', updated_at: comment.created_at,
    head: { sha: head }, base: { ref: 'main', repo: { full_name: config.repository } } };
  const runs = [];
  const writes = [];
  const api = { async gh(path, method, body) {
    if (method === 'POST') {
      writes.push(body);
      runs.push({ ...body, id: runs.length + 1, app: { slug: 'github-actions' } });
      return runs.at(-1);
    }
    if (method === 'PATCH') { Object.assign(runs.find((run) => path.endsWith(`/${run.id}`)), body); return {}; }
    if (path.includes('/check-runs')) return { check_runs: runs.filter((run) => run.head_sha === pull.head.sha) };
    if (path.includes('/issues/comments/')) return structuredClone(comment);
    if (path.includes('/issues/72/comments')) return [structuredClone(comment)];
    return structuredClone(pull);
  }, async yt() { throw new Error('Standalone PR must not access tracker'); } };
  const event = { action: 'created', repository: { full_name: config.repository }, issue: { number: 72, pull_request: {} }, comment: structuredClone(comment) };
  return { api, pull, comment, event, runs, writes };
}

test('bare review persists a verified head binding, is idempotent and survives a new process', async () => {
  const f = fixture();
  await captureReviewBinding(f.api, config, f.pull, f.event);
  await captureReviewBinding(f.api, config, f.pull, f.event);
  assert.equal(f.writes.length, 1);
  const decision = await readHumanDecision(f.api, config, f.pull, [f.comment]);
  assert.equal(decision.head_sha, head);
  assert.equal(decision.comment_id, 42);
  assert.ok(decision.recorded_at);
  assert.match(f.runs[0].output.title, new RegExp(head));
  assert.equal(f.comment.body, '/reviewed');
});

test('workflow accepts bare review but never binds it again after a push or event replay', async () => {
  const f = fixture();
  await handleEvent(f.api, config, f.event, false);
  assert.equal(f.runs.find((run) => run.name === 'human-review').conclusion, 'success');
  f.pull.head.sha = 'b'.repeat(40);
  f.pull.updated_at = '2026-10-09T12:01:00Z';
  await handleEvent(f.api, config, f.event, false);
  assert.equal(f.writes.filter((run) => run.name.startsWith('human-review-record-')).length, 1);
  assert.equal(f.runs.find((run) => run.name === 'human-review' && run.head_sha === f.pull.head.sha).conclusion, 'failure');
  f.comment.body = `/reviewed ${f.pull.head.sha}`;
  f.comment.created_at = f.comment.updated_at = '2026-10-09T12:02:00Z';
  await handleEvent(f.api, config, { repository: f.event.repository, pull_request: { number: 72 } }, false);
  assert.equal(f.runs.find((run) => run.name === 'human-review' && run.head_sha === f.pull.head.sha).conclusion, 'success');
});

test('delayed, closed, edited, unauthorized, wrong-issue and non-created comments cannot create a binding', async () => {
  for (const mutate of [
    (f) => { f.pull.updated_at = '2026-10-09T12:01:00Z'; },
    (f) => { f.pull.state = 'closed'; f.pull.merged = true; },
    (f) => { f.comment.updated_at = '2026-10-09T12:01:00Z'; },
    (f) => { f.comment.user.type = 'Bot'; },
    (f) => { f.comment.user.login = 'attacker'; },
    (f) => { f.comment.issue_url = 'https://api.github.com/repos/other/repo/issues/72'; },
    (f) => { f.event.action = 'edited'; },
    (f) => { f.event.action = 'deleted'; },
    (f) => { f.comment.body = `/reviewed ${head}`; f.event.comment.body = f.comment.body; },
  ]) {
    const f = fixture(); mutate(f);
    await captureReviewBinding(f.api, config, f.pull, f.event);
    assert.equal(f.writes.length, 0);
  }
});

test('a head change during capture prevents registration', async () => {
  const f = fixture();
  const original = f.api.gh;
  f.api.gh = (path, ...args) => path.endsWith('/pulls/72') ? Promise.resolve({ ...f.pull, head: { sha: 'b'.repeat(40) } }) : original(path, ...args);
  await captureReviewBinding(f.api, config, f.pull, f.event);
  assert.equal(f.writes.length, 0);
});

test('deletion, editing and bare revocation invalidate an existing automatic review', async () => {
  const f = fixture();
  await captureReviewBinding(f.api, config, f.pull, f.event);
  assert.equal(await readHumanDecision(f.api, config, f.pull, []), null);
  assert.equal(await readHumanDecision(f.api, config, f.pull, [{ ...f.comment, updated_at: '2026-10-09T12:01:00Z' }]), null);
  const revoke = { ...f.comment, id: 43, body: '/revoke-review', created_at: '2026-10-09T12:02:00Z', updated_at: '2026-10-09T12:02:00Z' };
  assert.equal(await readHumanDecision(f.api, config, f.pull, [f.comment, revoke]), null);
});

test('missing, forged, malformed or duplicate receipts never count as human approval', async () => {
  const f = fixture();
  assert.equal(activeHumanDecision([f.comment], head, config.humanReviewers), null);
  await captureReviewBinding(f.api, config, f.pull, f.event);
  const receipt = structuredClone(f.runs[0]);
  for (const change of [{ app: { slug: 'evil' } }, { head_sha: 'b'.repeat(40) }, { output: { summary: 'invalid' } }, { output: { summary: 'null' } }, { conclusion: 'failure' }, { external_id: 'wrong' }]) {
    f.runs.splice(0, f.runs.length, { ...receipt, ...change });
    assert.equal(await readHumanDecision(f.api, config, f.pull, [f.comment]), null);
  }
  f.runs.splice(0, f.runs.length, receipt, receipt);
  assert.equal(await readHumanDecision(f.api, config, f.pull, [f.comment]), null);
});

test('receipt needs readback; completion rejects binding recorded after merge', async () => {
  const f = fixture();
  const original = f.api.gh;
  f.api.gh = (path, method, body) => method === 'POST' ? Promise.resolve({}) : original(path, method, body);
  await assert.rejects(captureReviewBinding(f.api, config, f.pull, f.event), /not verified/);
  f.api.gh = original;
  await captureReviewBinding(f.api, config, f.pull, f.event);
  const decision = await readHumanDecision(f.api, config, f.pull, [f.comment]);
  const checks = [...config.requiredChecks, 'resolved-conversations'].map((name) => ({ name, passed: true }));
  const merged = { ...f.pull, merged: true, merged_at: '2026-10-09T12:05:00Z', merge_commit_sha: 'c'.repeat(40), merged_by: { type: 'User', login: 'chrystiamjr' } };
  assert.equal(canComplete(merged, { ...decision, recorded_at: '2026-10-09T12:03:00Z' }, checks, config), true);
  assert.equal(canComplete(merged, { ...decision, recorded_at: '2026-10-09T12:06:00Z' }, checks, config), false);
  assert.equal((await readReviewBindings(f.api, config, f.pull)).length, 1);
});

test('tracker completion consumes the same persisted automatic review after a human merge', async () => {
  const f = fixture();
  await captureReviewBinding(f.api, config, f.pull, f.event);
  f.pull.body = `YouTrack: https://${config.youtrackHost}/issue/GFRM-23`;
  f.pull.user = { login: 'chrystiamjr' };
  f.pull.head.repo = { full_name: config.repository };
  f.pull.head.ref = 'feat/optional-review-sha';
  f.pull.html_url = `https://github.com/${config.repository}/pull/72`;
  Object.assign(f.pull, { state: 'closed', merged: true, merge_commit_sha: 'c'.repeat(40),
    merged_at: new Date(Date.now() + 60000).toISOString(), merged_by: { login: 'chrystiamjr', type: 'User' } });
  for (const name of config.requiredChecks) f.runs.push({ name, head_sha: head, status: 'completed', conclusion: 'success', app: { slug: 'github-actions' } });
  const original = f.api.gh;
  f.api.gh = (path, ...args) => path === '/graphql' ? Promise.resolve({ data: { repository: { pullRequest: {
    reviewThreads: { nodes: [], pageInfo: { hasNextPage: false } } } } } }) : original(path, ...args);
  let state = 'Review';
  const comments = [];
  f.api.yt = async (path, method, body) => {
    if (path.startsWith('/api/users/me')) return { id: 'automation' };
    if (path.includes('/comments')) {
      if (method === 'POST') {
        if (comments.length) comments[0].text = body.text;
        else comments.push({ id: '7-1', text: body.text, author: { id: 'automation' } });
      }
      return comments;
    }
    if (path === '/api/commands') state = body.query.split(' ').at(-1);
    return { customFields: [{ name: config.stateField, value: { name: state } }] };
  };
  const result = await syncTicket(f.api, config, { action: 'merge', number: 72, apply: true, enabled: true });
  assert.equal(result.complete, true);
  assert.equal(state, 'Done');
  assert.match(comments[0].text, /Human review: https:\/\/github.com\/example\/comment\/42/);
});
