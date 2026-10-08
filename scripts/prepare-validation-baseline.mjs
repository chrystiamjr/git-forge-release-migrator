#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { realpathSync } from 'node:fs';
import { redactLog } from './ticket-validation.mjs';

export async function prepareBaseline(base, directory) {
  if (!/^[a-f0-9]{40}$/.test(base || '')) throw new Error('Baseline needs immutable commit SHA');
  const location = resolve(directory);
  await mkdir(location, { recursive: true });
  const tree = join(location, 'worktree');
  const sdk = fileURLToPath(new URL('./run-dart.js', import.meta.url));
  const runner = fileURLToPath(new URL('./run-ticket-checks.mjs', import.meta.url));
  const commands = [
    ['git', ['worktree', 'add', '--detach', tree, base], process.cwd()],
    ['yarn', ['install', '--immutable'], tree],
    ['node', [sdk, 'pub', 'get'], join(tree, 'dart_cli')],
    ['node', [sdk, '--flutter', 'pub', 'get'], join(tree, 'gui')],
    ['node', [runner, '--baseline-only', '--out', join(location, 'reports')], tree],
  ];
  let log = '';
  for (const [command, args, cwd] of commands) {
    const result = spawnSync(command, args, { cwd, env: command === 'yarn' ? { ...process.env, HUSKY: '0' } : process.env, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
    log += redactLog(`${result.stdout || ''}${result.stderr || ''}`);
    await writeFile(join(location, 'setup.log'), log);
    if (result.status !== 0) throw new Error('Baseline setup/measurement failed; inspect sanitized setup log');
  }
  return join(location, 'reports', `baseline-${base}`, 'validation-report.json');
}

if (process.argv[1] && process.argv[1] !== '-' && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
  prepareBaseline(process.argv[2], process.argv[3]).then(console.log).catch(() => { console.error('Baseline preparation failed; no comparison claimed.'); process.exitCode = 1; });
}
