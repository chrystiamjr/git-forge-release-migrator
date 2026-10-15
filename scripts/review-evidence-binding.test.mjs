import test from 'node:test';
import assert from 'node:assert/strict';
import { collectReviewEvidence } from './review-evidence.mjs';
import { renderChecklist } from './review-checklist.mjs';

const head = 'a'.repeat(40);
const eventBase = 'b'.repeat(40);
const testedBase = 'c'.repeat(40);
const merge = 'd'.repeat(40);

function fixture({ liveBase = testedBase, reportBase = testedBase, attempt = 1, parents = [testedBase, head] } = {}) {
  const run = { id: 123, run_attempt: 1, head_sha: head, status: 'completed', pull_requests: [{ number: 1 }] };
  const report = {
    schema_version: 1, head_sha: merge, pr_head_sha: head, pr_base_sha: reportBase, base_sha: reportBase,
    ci_run_id: 123, ci_run_attempt: attempt, checks: [{ name: 'dart-tests', status: 'passed' }],
    tests: [{ suite: 'dart', file: 'dart_cli/test/example_test.dart', name: 'resumes failed items', status: 'passed' }],
  };
  const request = async (path) => {
    if (path.endsWith('/pulls/1')) return { state: 'open', head: { sha: head }, base: { ref: 'main', sha: eventBase } };
    if (path.includes('/git/ref/heads/')) return { object: { type: 'commit', sha: liveBase } };
    if (path.includes('/git/commits/')) return { parents: parents.map((sha) => ({ sha })) };
    if (path.includes('/jobs?')) return { jobs: [{ name: 'gui-visual', conclusion: 'success' }] };
    if (path.includes('/workflows/')) return { workflow_runs: [run] };
    throw new Error(`Unexpected request: ${path}`);
  };
  return { report, request };
}

test('a stale PR base snapshot does not discard evidence for the actual tested and live base', async () => {
  const f = fixture();
  const evidence = await collectReviewEvidence('o/r', 1, head, f.request, async () => f.report);
  const body = renderChecklist({ head, files: [], requirements: [{
    id: 'retry', description: 'Resumes failed items', suite: 'dart', test_file: 'dart_cli/test/example_test.dart',
    test_name: 'resumes failed items', implementation_verified: true, evidence: 'Test implementation inspected',
  }], assessmentHead: head, evidence, reviewed: true });
  assert.match(body, /\[x\] Dart test suite/);
  assert.match(body, /\[x\] Canonical macOS visual tests/);
  assert.match(body, /\[x\] Resumes failed items/);
});

test('base movement, mislabeled reports, stale attempts and unrelated merge parents remain pending', async () => {
  for (const change of [
    { liveBase: 'e'.repeat(40) }, { reportBase: eventBase }, { attempt: 0 }, { parents: [testedBase, 'f'.repeat(40)] },
  ]) {
    const f = fixture(change);
    const evidence = await collectReviewEvidence('o/r', 1, head, f.request, async () => f.report);
    assert.equal(evidence.checks['gui-goldens'].status, 'pending');
    assert.equal(evidence.tests.length, 0);
    assert.match(evidence.reason, /current PR head and target branch/);
    const body = renderChecklist({ head, files: [], requirements: [], evidence });
    assert.match(body, /Refresh the PR and run Quality Checks again/);
    assert.doesNotMatch(body, /\[x\]/);
  }
});

test('unavailable or malformed target refs never fall back to the stale PR base snapshot', async () => {
  const f = fixture();
  for (const target of [{ object: { type: 'tag', sha: testedBase } }, { object: { type: 'commit', sha: 'invalid' } }]) {
    const request = (path) => path.includes('/git/ref/heads/') ? target : f.request(path);
    const evidence = await collectReviewEvidence('o/r', 1, head, request, async () => f.report);
    assert.deepEqual(evidence.checks, {});
    assert.equal(evidence.tests.length, 0);
  }
  await assert.rejects(collectReviewEvidence('o/r', 1, head, (path) => {
    if (path.includes('/git/ref/heads/')) throw new Error('Target ref unavailable');
    return f.request(path);
  }, async () => f.report), /Target ref unavailable/);
});
