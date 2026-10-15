import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { checklistMetadata, renderChecklist, updateChecklist } from './review-checklist.mjs';
import { handleReviewEvent } from './review-event.mjs';

const head = 'a'.repeat(40);
const timestamp = '2026-10-15T20:12:00.000Z';
const progress = (phase, run_id = 10, run_attempt = 1) => ({
  phase, run_id, run_attempt, updated_at: timestamp,
  url: `https://github.com/o/r/actions/runs/${run_id}`,
});

function fixture() {
  const state = { head, comments: [], writes: [], closed: false, changeBeforeWrite: false };
  const request = async (path, options = {}) => {
    if (path === '/repos/o/r/pulls/1') {
      return { state: state.closed ? 'closed' : 'open', head: { sha: state.head } };
    }
    if (options.method) {
      const body = JSON.parse(options.body).body;
      state.writes.push({ path, method: options.method, body });
      state.comments = [{ id: 12, user: { login: 'bot' }, body, html_url: 'https://github.com/o/r/pull/1#issuecomment-12' }];
      return state.comments[0];
    }
    if (path.includes('/issues/1/comments?')) return state.comments;
    if (path.includes('/pulls/1/files?')) {
      if (state.changeBeforeWrite) state.head = 'b'.repeat(40);
      return [{ filename: 'gui/test/e2e/runtime_progress_results_test.dart' }];
    }
    throw new Error(`Unexpected request: ${path}`);
  };
  return { state, request, update: (options = {}) => updateChecklist({
    repository: 'o/r', number: 1, head: state.head, botLogin: 'bot', request, ...options,
  }) };
}

test('the persistent checklist renders every review phase with timestamp and workflow link', () => {
  const phases = {
    waiting_ci: 'Waiting for CI', preparing: 'Preparing review', evaluating: 'Evaluation queued or running',
    publishing: 'Publishing results', completed: 'Review complete', failed: 'Review failed',
    cancelled: 'Review cancelled', skipped: 'Review skipped',
  };
  for (const [phase, label] of Object.entries(phases)) {
    const body = renderChecklist({ head, files: [], requirements: [], progress: progress(phase) });
    assert.ok(body.includes(`**Automated review:** ${label}`));
    assert.ok(body.includes(timestamp));
    assert.ok(body.includes('https://github.com/o/r/actions/runs/10'));
    assert.equal(checklistMetadata(body).progress.phase, phase);
    assert.doesNotMatch(body, /\[x\]/);
  }
});

test('phase updates edit one owned comment and preserve evidence and review-specific requirements', async () => {
  const { state, update } = fixture();
  const requirement = { id: 'success', description: 'Success reaches Results', suite: 'gui',
    test_file: 'gui/test/e2e/example_test.dart', test_name: 'successful run',
    implementation_verified: true, evidence: 'Inspected the routed runtime test' };
  const evidence = { head, checks: { 'dart-tests': { status: 'passed' } }, tests: [
    { suite: 'gui', file: requirement.test_file, name: requirement.test_name, status: 'passed' },
  ] };
  await update({ evidence, llm: { test_requirements: [requirement] }, progress: progress('preparing') });
  for (const phase of ['evaluating', 'publishing', 'completed']) await update({ progress: progress(phase) });
  assert.equal(state.writes.filter((write) => write.method === 'POST').length, 1);
  assert.equal(state.writes.filter((write) => write.method === 'PATCH').length, 3);
  const body = state.comments[0].body;
  assert.match(body, /\[x\] Dart test suite/);
  assert.match(body, /\[x\] Success reaches Results/);
  assert.equal(checklistMetadata(body).progress.phase, 'completed');
  assert.equal(checklistMetadata(body).reviewed, true);
});

test('delayed phases, old runs and old attempts cannot overwrite current or terminal progress', async () => {
  const { state, update } = fixture();
  await update({ progress: progress('completed', 10, 2) });
  for (const incoming of [progress('preparing', 10, 2), progress('failed', 10, 2),
    progress('publishing', 10, 1), progress('evaluating', 9, 3), progress('waiting_ci', 0)]) {
    await update({ progress: incoming });
  }
  assert.equal(state.writes.length, 1);
  await update({ progress: progress('preparing', 10, 3) });
  assert.equal(checklistMetadata(state.comments[0].body).progress.run_attempt, 3);
  await update({ progress: progress('evaluating', 11) });
  assert.equal(checklistMetadata(state.comments[0].body).progress.run_id, 11);
});

test('a new PR head resets progress and previous checkmarks', async () => {
  const { state, update } = fixture();
  await update({ evidence: { head, checks: { 'dart-tests': { status: 'passed' } } }, progress: progress('completed') });
  state.head = 'b'.repeat(40);
  await update({ progress: progress('waiting_ci', 0) });
  const body = state.comments[0].body;
  assert.equal(checklistMetadata(body).head, state.head);
  assert.equal(checklistMetadata(body).progress.phase, 'waiting_ci');
  assert.doesNotMatch(body, /\[x\]/);
});

test('progress still obeys closed and just-superseded PR guards', async () => {
  for (const change of ['closed', 'changeBeforeWrite']) {
    const { state, update } = fixture();
    state[change] = true;
    await assert.rejects(update({ head, progress: progress('evaluating') }), /PR closed, merged, or changed/);
    assert.equal(state.writes.length, 0);
  }
});

const env = { GITHUB_REPOSITORY: 'o/r', PR_NUMBER: '1', REVIEW_BOT_LOGIN: 'bot',
  GITHUB_RUN_ID: '10', GITHUB_RUN_ATTEMPT: '1', REVIEW_PROGRESS_PHASE: 'evaluating' };
const event = { workflow_run: { head_sha: head } };

test('workflow progress events update the owned checklist and tolerate publication outages', async (t) => {
  const { state, request } = fixture();
  await handleReviewEvent(event, 'progress', env, request);
  assert.equal(checklistMetadata(state.comments[0].body).progress.phase, 'evaluating');
  const warnings = [];
  t.mock.method(console, 'warn', (message) => warnings.push(message));
  await handleReviewEvent(event, 'progress', env, async () => { throw new Error('API unavailable'); });
  assert.match(warnings[0], /Review progress unavailable: API unavailable/);
});

test('initial lifecycle status links to checks; stale triggering heads cannot be overridden', async (t) => {
  const { state, request } = fixture();
  await handleReviewEvent({ pull_request: { number: 1, head: { sha: head } } }, 'checklist', env, request);
  const metadata = checklistMetadata(state.comments[0].body);
  assert.equal(metadata.progress.phase, 'waiting_ci');
  assert.equal(metadata.progress.url, 'https://github.com/o/r/pull/1/checks');
  t.mock.method(console, 'log', () => {});
  await handleReviewEvent({ workflow_run: { head_sha: 'b'.repeat(40) } }, 'progress',
    { ...env, REVIEW_EXPECTED_HEAD: head }, request);
  assert.equal(state.writes.length, 1);
});

test('terminal progress distinguishes a completed review with findings from unavailable analysis', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'gfrm-progress-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const resultPath = join(directory, 'result.json');
  for (const [result, expected] of [
    [{ verdict: 'request_changes' }, 'completed'],
    [{ error: 'Missing result' }, 'failed'],
    [{ llm: { error: 'Model unavailable' } }, 'failed'],
    [{ verdict: 'skip' }, 'skipped'],
    [{ verdict: 'skip', head_sha: undefined }, 'skipped'],
  ]) {
    const { state, request } = fixture();
    await writeFile(resultPath, JSON.stringify({ head_sha: head, ...result }));
    await handleReviewEvent(event, 'progress', { ...env, REVIEW_PROGRESS_PHASE: 'completed',
      REVIEW_RESULT_PATH: resultPath }, request);
    assert.equal(checklistMetadata(state.comments[0].body).progress.phase, expected);
  }
  const { state, request } = fixture();
  await handleReviewEvent(event, 'progress', { ...env, REVIEW_PROGRESS_PHASE: 'cancelled' }, request);
  assert.equal(checklistMetadata(state.comments[0].body).progress.phase, 'cancelled');
});
