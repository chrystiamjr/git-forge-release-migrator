import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveCiRevision, main } from './ci-validation-revision.mjs';
import { collectReviewEvidence } from './review-evidence.mjs';
import { renderChecklist } from './review-checklist.mjs';

function mergeFixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'gfrm-ci-revision-'));
  const cwd = join(directory, 'repo');
  mkdirSync(cwd);
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const env = { ...process.env };
  for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR']) delete env[key];
  const git = (...args) => execFileSync('git', args, { cwd, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('init', '--initial-branch=main');
  git('config', 'user.name', 'CI fixture');
  git('config', 'user.email', 'ci@example.test');
  git('config', 'commit.gpgsign', 'false');
  git('config', 'core.hooksPath', '/dev/null');
  writeFileSync(join(cwd, 'base'), 'initial\n');
  git('add', '.'); git('commit', '-m', 'initial');
  const eventBase = git('rev-parse', 'HEAD');
  git('checkout', '-b', 'feature');
  writeFileSync(join(cwd, 'feature'), 'change\n');
  git('add', '.'); git('commit', '-m', 'feature');
  const head = git('rev-parse', 'HEAD');
  git('checkout', 'main');
  writeFileSync(join(cwd, 'base'), 'advanced\n');
  git('add', '.'); git('commit', '-m', 'base advanced');
  const base = git('rev-parse', 'HEAD');
  git('merge', '--no-ff', 'feature', '-m', 'test merge');
  const revision = git('rev-parse', 'HEAD');
  return { directory, cwd, env, eventBase, base, head, revision, parents: git('show', '-s', '--format=%P', 'HEAD').split(' ') };
}

test('producer derives baseline and report base from the actual merge after the target advances', async (t) => {
  const f = mergeFixture(t);
  const environmentFile = join(f.directory, 'environment');
  const result = await main({
    ...f.env, GITHUB_ENV: environmentFile, GITHUB_SHA: f.revision,
    CI_PR_HEAD_SHA: f.head, CI_PR_BASE_SHA: f.eventBase,
    GIT_DIR: '/unrelated/git/directory',
  }, f.cwd);
  assert.deepEqual(result, { tested_sha: f.revision, pr_head_sha: f.head, pr_base_sha: f.base });
  assert.equal(readFileSync(environmentFile, 'utf8'), `CI_PR_HEAD_SHA=${f.head}\nCI_PR_BASE_SHA=${f.base}\n`);
  assert.notEqual(f.base, f.eventBase);
  const report = {
    schema_version: 1, head_sha: result.tested_sha, pr_head_sha: result.pr_head_sha,
    pr_base_sha: result.pr_base_sha, base_sha: result.pr_base_sha, ci_run_id: 123, ci_run_attempt: 1,
    checks: [{ name: 'dart-tests', status: 'passed' }],
  };
  const evidence = await collectReviewEvidence('o/r', 1, f.head, async (path) => {
    if (path.endsWith('/pulls/1')) return { state: 'open', head: { sha: f.head }, base: { ref: 'main', sha: f.eventBase } };
    if (path.includes('/git/ref/heads/')) return { object: { type: 'commit', sha: f.base } };
    if (path.includes('/git/commits/')) return { parents: f.parents.map((sha) => ({ sha })) };
    if (path.includes('/jobs?')) return { jobs: [{ name: 'gui-visual', conclusion: 'success' }] };
    return { workflow_runs: [{ id: 123, run_attempt: 1, status: 'completed', head_sha: f.head, pull_requests: [{ number: 1 }] }] };
  }, async () => report);
  const checklist = renderChecklist({ head: f.head, files: [], requirements: [], evidence });
  assert.match(checklist, /\[x\] Dart test suite/);
  assert.match(checklist, /\[x\] Canonical macOS visual tests/);
});

test('revision binding refuses a different checkout, wrong PR parent and non-merge commits', () => {
  const context = { revision: 'a'.repeat(40), expectedRevision: 'a'.repeat(40), expectedHead: 'b'.repeat(40),
    parents: ['c'.repeat(40), 'b'.repeat(40)] };
  for (const mismatch of [
    { expectedRevision: 'd'.repeat(40) }, { expectedHead: 'd'.repeat(40) },
    { parents: [context.expectedHead] }, { parents: [...context.parents, 'd'.repeat(40)] },
    { parents: [...context.parents].reverse() }, { parents: [context.expectedHead, context.expectedHead] },
    { parents: ['malformed', context.expectedHead] }, { expectedHead: '' },
  ]) assert.throws(() => resolveCiRevision({ ...context, ...mismatch }));
});

test('the validation runner rejects inconsistent PR metadata before writing reports or running suites', (t) => {
  const f = mergeFixture(t);
  const runner = fileURLToPath(new URL('./run-ticket-checks.mjs', import.meta.url));
  for (const [base, declaredBase] of [[f.eventBase, f.eventBase], [f.base, f.eventBase]]) {
    const out = join(f.directory, `invalid-${base}`);
    const result = spawnSync(process.execPath, [runner, '--ci-core', '--ticket', 'LOCAL-test', '--base', base, '--out', out], {
      cwd: f.cwd, encoding: 'utf8', env: {
        ...f.env, CI: 'true', GITHUB_EVENT_NAME: 'pull_request', GITHUB_SHA: f.revision,
        CI_PR_HEAD_SHA: f.head, CI_PR_BASE_SHA: declaredBase,
      },
    });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Ticket validation failed/);
    assert.equal(existsSync(out), false, 'Reject identity mismatches before collecting test evidence');
  }
});
