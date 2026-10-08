import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { eventNumber, handleEvent, publishCheck } from './ticket-delivery-event.mjs';
const config = JSON.parse(await readFile(new URL('../.github/ticket-delivery.json', import.meta.url), 'utf8'));

test('delivery CLI modules can be imported from stdin without executing their commands', () => {
  const modules = ['run-ticket-checks.mjs', 'ticket-pr-sync.mjs', 'ticket-delivery-event.mjs', 'prepare-validation-baseline.mjs'];
  const input = modules.map((name) => `await import(${JSON.stringify(new URL(name, import.meta.url).href)});`).join('\n');
  const result = spawnSync(process.execPath, ['--input-type=module', '-'], { input, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, '');
});

test('only validated PR metadata events are accepted; issue comments are not executable commands', () => {
  assert.equal(eventNumber({ repository: { full_name: config.repository }, issue: { number: 1 } }, config.repository), null);
  assert.equal(eventNumber({ repository: { full_name: config.repository }, issue: { number: 68, pull_request: {}, body: '$(steal-secrets)' } }, config.repository), 68);
  assert.throws(() => eventNumber({ repository: { full_name: 'evil/repo' }, pull_request: { number: 68 } }, config.repository));
  assert.throws(() => eventNumber({ repository: { full_name: config.repository }, pull_request: { number: '$(bad)' } }, config.repository));
});

test('owned checks update idempotently without changing another app check', async () => {
  const pull = { number: 68, head: { sha: 'a'.repeat(40) } };
  const external = `gfrm-delivery:68:${pull.head.sha}:human-review`;
  const calls = [];
  const api = { async gh(path, method, body) {
    if (method) { calls.push({ path, method, body }); return {}; }
    return { check_runs: [{ id: 1, external_id: external, app: { slug: 'other' } }, { id: 2, external_id: external, app: { slug: 'github-actions' } }] };
  } };
  await publishCheck(api, config, pull, 'human-review', false, 'pending');
  assert.ok(calls[0].path.endsWith('/2'));
  assert.equal(calls[0].method, 'PATCH');
  assert.equal(calls[0].body.conclusion, 'failure');
});

test('standalone process PR still requires human decision and never writes tracker', async () => {
  const writes = [];
  const p = { number: 69, body: 'Process plan: LOCAL-delivery-contract', head: { sha: 'a'.repeat(40) }, base: { ref: 'main', repo: { full_name: config.repository } } };
  const api = { async gh(path, method, body) {
    if (method) { writes.push(body); return {}; }
    if (path.endsWith('/pulls/69')) return p;
    return path.includes('/check-runs') ? { check_runs: [] } : [];
  }, async yt() { throw new Error('Tracker must not be called'); } };
  const result = await handleEvent(api, config, { repository: { full_name: config.repository }, pull_request: { number: 69 } }, true);
  assert.equal(result.status, 'not_applicable');
  assert.equal(writes.find((row) => row.name === 'human-review').conclusion, 'failure');
  assert.equal(writes.find((row) => row.name === 'ticket-link').conclusion, 'success');
});

test('privileged workflows checkout trusted default branch and install no head dependencies', async () => {
  const workflow = await readFile(new URL('../.github/workflows/ticket-delivery.yml', import.meta.url), 'utf8');
  assert.match(workflow, /ref: \$\{\{ github.event.repository.default_branch \}\}/);
  assert.doesNotMatch(workflow, /head\.sha|yarn install|npm install/);
});

import { auxiliaryReviewContexts } from './review-pr.mjs';
test('auxiliary bot cannot deadlock solo human review; quality gates remain required', () => {
  assert.deepEqual(auxiliaryReviewContexts(['test', 'ticket-validation', 'human-review', 'ticket-link']), ['test', 'ticket-validation']);
});
