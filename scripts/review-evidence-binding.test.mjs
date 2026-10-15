import test from 'node:test';
import assert from 'node:assert/strict';
import { collectReviewEvidence } from './review-evidence.mjs';
import { renderChecklist } from './review-checklist.mjs';

const head = 'a'.repeat(40);
const eventBase = 'b'.repeat(40);
const testedBase = 'c'.repeat(40);
const merge = 'd'.repeat(40);

function fixture({ liveBase = testedBase, reportBase = testedBase, attempt = 1, parents = [testedBase, head],
  ref = 'main', visualConclusion = 'success' } = {}) {
  const run = { id: 123, run_attempt: 1, head_sha: head, status: 'completed', pull_requests: [{ number: 1 }] };
  const report = {
    schema_version: 1, head_sha: merge, pr_head_sha: head, pr_base_sha: reportBase, base_sha: reportBase,
    ci_run_id: 123, ci_run_attempt: attempt, checks: [{ name: 'dart-tests', status: 'passed' }],
    tests: [{ suite: 'dart', file: 'dart_cli/test/example_test.dart', name: 'resumes failed items', status: 'passed' }],
  };
  const request = async (path) => {
    if (path.endsWith('/pulls/1')) return { state: 'open', head: { sha: head }, base: { ref, sha: eventBase } };
    if (path.includes('/git/ref/heads/')) return { object: { type: 'commit', sha: liveBase } };
    if (path.includes('/git/commits/')) return { parents: parents.map((sha) => ({ sha })) };
    if (path.includes('/jobs?')) return { jobs: [{ name: 'gui-visual', conclusion: visualConclusion }] };
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
    const body = renderChecklist({ head, files: [], requirements: [], evidence });
    assert.match(body, change.attempt === 0 ? /another run or attempt/ : /Update the PR branch/);
    assert.doesNotMatch(body, /\[x\]/);
  }
});

test('report failures explain their cause without recommending a branch update for artifact problems', async (t) => {
  t.mock.method(console, 'warn', () => {});
  const cases = [
    { load: async () => null, reason: /No validation report is available/ },
    { load: async () => { throw new Error('Artifact access failed'); }, reason: /could not be loaded/ },
    { patch: { ci_run_id: 999 }, reason: /another run or attempt/ },
    { patch: { ci_run_attempt: 0 }, reason: /another run or attempt/ },
    { patch: { head_sha: 'invalid' }, reason: /invalid tested revision/ },
    { patch: { schema_version: 99 }, reason: /unsupported format/ },
    { patch: { baseline: true }, reason: /unsupported format/ },
  ];
  for (const scenario of cases) {
    const f = fixture();
    const report = { ...f.report, ...scenario.patch };
    const evidence = await collectReviewEvidence('o/r', 1, head, f.request, scenario.load || (async () => report));
    assert.equal(evidence.checks['gui-goldens'].status, 'pending');
    assert.equal(evidence.tests.length, 0);
    assert.match(evidence.reason, scenario.reason);
    assert.equal(evidence.checks['gui-goldens'].reason, evidence.reason);
    assert.doesNotMatch(evidence.reason, /Refresh the PR|Update the PR branch/);
  }
});

test('slash-named target refs preserve separators and encode special characters within each segment', async () => {
  for (const [ref, encoded] of [['release/1.2', 'release/1.2'], ['release/1.2+hotfix#1', 'release/1.2%2Bhotfix%231']]) {
    const f = fixture({ ref });
    const paths = [];
    const evidence = await collectReviewEvidence('o/r', 1, head, (path) => {
      if (path.includes('/git/ref/heads/')) paths.push(path);
      return f.request(path);
    }, async () => f.report);
    assert.deepEqual(paths, [`/repos/o/r/git/ref/heads/${encoded}`]);
    assert.equal(evidence.checks['dart-tests'].status, 'passed');
  }
});

test('unresolved target refs retain a reason and actual visual failures without certifying stale evidence', async () => {
  for (const visualConclusion of ['success', 'failure']) {
    for (const cause of ['missing-name', 'wrong-type', 'invalid-sha', 'lookup-failed', 'empty-response']) {
      const f = fixture({ visualConclusion, ref: cause === 'missing-name' ? null : 'main' });
      const evidence = await collectReviewEvidence('o/r', 1, head, (path) => {
        if (path.includes('/git/ref/heads/')) {
          if (cause === 'lookup-failed') throw new Error('Target ref unavailable');
          if (cause === 'empty-response') return null;
          return { object: { type: cause === 'wrong-type' ? 'tag' : 'commit', sha: cause === 'wrong-type' ? testedBase : 'invalid' } };
        }
        return f.request(path);
      }, async () => f.report);
      assert.equal(evidence.checks['gui-goldens'].status, visualConclusion === 'success' ? 'pending' : 'failure');
      assert.equal(evidence.checks['dart-tests'], undefined);
      assert.equal(evidence.tests.length, 0);
      assert.match(evidence.reason, /Target branch ref could not be resolved/);
      const body = renderChecklist({ head, files: [], requirements: [], evidence });
      assert.match(body, /Target branch ref could not be resolved/);
      assert.doesNotMatch(body, /\[x\]/);
    }
  }
});
