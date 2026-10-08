import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifyChanges, coverageResult, evaluateEvidence, inspectSecrets, readCoverage, redactLog } from './ticket-validation.mjs';
import { parseOptions } from './run-ticket-checks.mjs';

test('scope includes shared runtime consumers and native/live boundaries', () => {
  assert.equal(classifyChanges(['dart_cli/lib/src/application/run_service.dart']).gui, true);
  assert.equal(classifyChanges(['gui/lib/src/features/progress/presentation/page.dart']).visual, true);
  assert.equal(classifyChanges(['gui/windows/runner/main.cpp']).native, true);
  assert.equal(classifyChanges(['dart_cli/lib/src/providers/bitbucket.dart']).live, true);
  assert.equal(classifyChanges(['docs/engineering/testing-playbook.md']).live, false);
});

test('coverage excludes generated/dependency scope and handles zero hits', () => {
  const lcov = 'SF:lib/src/page.dart\nDA:1,1\nDA:2,0\nend_of_record\nSF:lib/src/page.g.dart\nDA:1,0\nend_of_record\nSF:test/fake.dart\nDA:1,1\nend_of_record';
  assert.deepEqual(readCoverage(lcov), { covered: 1, lines: 2, percent: 50 });
  assert.throws(() => readCoverage('SF:lib/x.dart\nend_of_record'));
  assert.equal(coverageResult({ percent: 79 }, null, false).status, 'failed');
  assert.equal(coverageResult({ percent: 90 }, null, true).status, 'pending');
  assert.equal(coverageResult({ percent: 90 }, { percent: 95 }, true).status, 'failed');
  assert.equal(coverageResult({ percent: 95 }, { percent: 95 }, true).status, 'passed');
});

test('secret diagnostics and logs never contain matched token', () => {
  const token = 'ghp_' + 'a'.repeat(30);
  const findings = inspectSecrets([{ filename: 'config.txt', patch: `@@ -0,0 +1 @@\n+${token}` }]);
  assert.equal(findings.length, 1);
  assert.ok(!JSON.stringify(findings).includes(token));
  assert.equal(redactLog(`Bearer ${token}`), 'Bearer [REDACTED]');
  assert.equal(redactLog('secretvalue', { YOUTRACK_TOKEN: 'secretvalue' }), '[REDACTED]');
});

test('real evidence requires same ticket/head, artifacts and successful scenario', () => {
  const context = { ticket: 'GFRM-23', head: 'a'.repeat(40), kind: 'native' };
  assert.equal(evaluateEvidence(null, context).status, 'pending');
  const evidence = { ticket: context.ticket, head_sha: context.head, kind: context.kind, status: 'passed', artifacts: [{ path: 'proof', sha256: 'hash' }] };
  assert.equal(evaluateEvidence(evidence, context).status, 'passed');
  assert.equal(evaluateEvidence({ ...evidence, head_sha: 'stale' }, context).status, 'pending');
});

test('options reject unknown flags and omitted ticket/base', () => {
  assert.throws(() => parseOptions(['--ticket', 'GFRM-23']));
  assert.throws(() => parseOptions(['--base', 'main', '--ticket', 'other']));
  assert.throws(() => parseOptions(['--skip-tests']));
  assert.equal(parseOptions(['--baseline-only']).baselineOnly, true);
});

import sdkRunner from './run-dart.js';
test('SDK invocation strips inherited Git context without mutating process environment', () => {
  const previous = process.env.GIT_DIR;
  process.env.GIT_DIR = '/an/unrelated/worktree/git-dir';
  try {
    const environment = sdkRunner.sdkEnvironment();
    assert.equal(environment.GIT_DIR, undefined);
    assert.equal(process.env.GIT_DIR, '/an/unrelated/worktree/git-dir');
    assert.equal(environment.PATH, process.env.PATH);
  } finally {
    if (previous === undefined) delete process.env.GIT_DIR;
    else process.env.GIT_DIR = previous;
  }
});

import { spawnSync } from 'node:child_process';
import { mkdtempSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
test('runner executes through symlink paths and invalid CLI returns nonzero', () => {
  const directory = mkdtempSync(join(tmpdir(), 'gfrm-runner-test-'));
  try {
    const link = join(directory, 'checks.mjs');
    symlinkSync(fileURLToPath(new URL('./run-ticket-checks.mjs', import.meta.url)), link);
    const result = spawnSync(process.execPath, [link, '--skip-tests'], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Ticket validation failed/);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
