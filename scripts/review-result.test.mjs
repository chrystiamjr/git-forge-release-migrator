import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ensureReviewResult } from './review-result.mjs';

const head = 'a'.repeat(40);

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'gfrm-review-result-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const env = { GITHUB_REPOSITORY: 'o/r', PR_NUMBER: '1', REVIEW_EXPECTED_HEAD: head,
    REVIEW_RESULT_PATH: join(directory, 'download', 'review.json'), GITHUB_RUN_ID: '42', GITHUB_RUN_ATTEMPT: '2' };
  const pull = { state: 'open', head: { sha: head } };
  const request = async (path, options) => {
    assert.equal(path, '/repos/o/r/pulls/1');
    assert.equal(options, undefined);
    return pull;
  };
  return { env, pull, request };
}

test('missing analysis or download produces a persisted head-bound blocking fallback', async (t) => {
  const f = await fixture(t);
  const result = await ensureReviewResult(f.env, f.request);
  assert.equal(result.verdict, 'request_changes');
  assert.equal(result.head_sha, head);
  assert.equal(result.pr_number, 1);
  assert.equal(result.publication_key, `42:2:${head}`);
  assert.deepEqual(JSON.parse(await readFile(f.env.REVIEW_RESULT_PATH, 'utf8')), result);
});

test('valid analysis and explicit skip survive fallback recovery unchanged', async (t) => {
  const f = await fixture(t);
  await ensureReviewResult(f.env, f.request);
  for (const verdict of ['approve', 'request_changes', 'wait', 'skip']) {
    const result = { verdict, pr_number: 1, ...(verdict === 'skip' ? {} : { head_sha: head }), findings: [] };
    const raw = JSON.stringify(result);
    await writeFile(f.env.REVIEW_RESULT_PATH, raw);
    assert.deepEqual(await ensureReviewResult(f.env, f.request), result);
    assert.equal(await readFile(f.env.REVIEW_RESULT_PATH, 'utf8'), raw);
  }
});

test('truncated or incorrectly bound analysis cannot be published as approval', async (t) => {
  const f = await fixture(t);
  await ensureReviewResult(f.env, f.request);
  for (const raw of ['{', 'null', JSON.stringify({ verdict: 'approve', pr_number: 2, head_sha: head }),
    JSON.stringify({ verdict: 'approve', pr_number: 1, head_sha: 'b'.repeat(40) })]) {
    await writeFile(f.env.REVIEW_RESULT_PATH, raw);
    assert.equal((await ensureReviewResult(f.env, f.request)).verdict, 'request_changes');
  }
});

test('fallback recovery skips closed, merged, and superseded PRs', async (t) => {
  for (const change of [{ state: 'closed' }, { merged: true }, { head: { sha: 'new' } }]) {
    const f = await fixture(t);
    Object.assign(f.pull, change);
    assert.equal((await ensureReviewResult(f.env, f.request)).verdict, 'skip');
  }
});

test('fallback recovery requires explicit revision binding and a successful live check', async (t) => {
  const f = await fixture(t);
  for (const change of [{ REVIEW_EXPECTED_HEAD: '' }, { PR_NUMBER: '0' }, { GITHUB_REPOSITORY: '' }]) {
    await assert.rejects(ensureReviewResult({ ...f.env, ...change }, f.request), /binding/);
  }
  await assert.rejects(ensureReviewResult(f.env, async () => { throw new Error('API unavailable'); }), /API unavailable/);
  await assert.rejects(readFile(f.env.REVIEW_RESULT_PATH), { code: 'ENOENT' });
});
