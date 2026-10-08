#!/usr/bin/env node
import { realpathSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  classifyChanges, coverageResult, evaluateEvidence, inspectSecrets, readCoverage, redactLog, requiredEvidence,
} from './ticket-validation.mjs';

export function parseOptions(args) {
  const options = {};
  const keys = new Set(['base', 'ticket', 'out', 'baseline-report', 'evidence-dir']);
  for (let index = 0; index < args.length; index++) {
    const key = args[index].replace(/^--/, '');
    if (args[index] === '--baseline-only') { options.baselineOnly = true; continue; }
    if (!args[index].startsWith('--') || !keys.has(key) || !args[index + 1] || args[index + 1].startsWith('--')) {
      throw new Error(`Invalid option: ${args[index]}`);
    }
    options[key] = args[++index];
  }
  if (!options.baselineOnly && (!options.base || !/^(GFRM-\d+|LOCAL-[a-z0-9-]+)$/.test(options.ticket || ''))) {
    throw new Error('Use --base <fixed revision> --ticket GFRM-N [--baseline-report <file>]');
  }
  return options;
}

function run(command, args, cwd) {
  const environment = { ...process.env };
  for (const name of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR']) delete environment[name];
  const result = spawnSync(command, args, { cwd, env: environment, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  return { exit: result.status ?? 1, output: `${result.stdout || ''}${result.stderr || ''}${result.error?.message || ''}` };
}

export async function main(args = process.argv.slice(2)) {
  const options = parseOptions(args);
  const cwd = process.cwd();
  const git = (...args) => {
    const result = run('git', args, cwd);
    if (result.exit !== 0) throw new Error(`Git operation failed: ${args[0]}`);
    return result.output.trim();
  };
  const head = git('rev-parse', 'HEAD');
  const base = options.baselineOnly ? head : git('rev-parse', '--verify', `${options.base}^{commit}`);
  const out = resolve(options.out || '.local/validation', `${options.baselineOnly ? 'baseline' : options.ticket}-${head}`);
  await mkdir(out, { recursive: true });
  const files = options.baselineOnly ? [] : [...new Set([
    ...git('diff', '--name-only', base).split('\n'),
    ...git('ls-files', '--others', '--exclude-standard').split('\n'),
  ].filter(Boolean))];
  const dirty = git('status', '--porcelain');
  if (dirty) throw new Error('Commit source before final validation; report must identify immutable tested head');
  const scope = options.baselineOnly ? { gui: true } : classifyChanges(files);
  let baseline;
  if (options['baseline-report']) {
    baseline = JSON.parse(await readFile(options['baseline-report'], 'utf8'));
    if (baseline.head_sha !== base || !baseline.baseline || baseline.status !== 'passed' || baseline.coverage_scope !== 'lib-excluding-generated-v1') {
      throw new Error('Baseline does not identify a passing comparable requested base');
    }
  }
  const report = {
    schema_version: 1, ticket: options.ticket || null, head_sha: head, base_sha: base, baseline: !!options.baselineOnly,
    coverage_scope: 'lib-excluding-generated-v1', created_at: new Date().toISOString(), scope, checks: [], coverage: {},
  };
  async function check(name, command, args, directory = cwd) {
    const result = run(command, args, directory);
    const output = redactLog(result.output);
    const log = `${name}.log`;
    await writeFile(join(out, log), output);
    report.checks.push({ name, status: result.exit === 0 ? 'passed' : 'failed', exit_code: result.exit, log, sha256: createHash('sha256').update(output).digest('hex') });
    return result.exit === 0;
  }
  async function coverage(kind, required) {
    try {
      const data = await readFile(join(cwd, kind === 'dart' ? 'dart_cli' : 'gui', 'coverage/lcov.info'), 'utf8');
      const current = readCoverage(data);
      report.coverage[kind] = current;
      const result = coverageResult(current, baseline?.coverage?.[kind], required && !options.baselineOnly);
      const artifact = `${kind}-lcov.info`;
      await writeFile(join(out, artifact), data);
      report.checks.push({ name: `${kind}-coverage`, ...result, artifact, sha256: createHash('sha256').update(data).digest('hex') });
    } catch {
      report.checks.push({ name: `${kind}-coverage`, status: 'failed', reason: 'Coverage collection missing or invalid' });
    }
  }
  const sdk = run('fvm', ['flutter', '--version'], cwd);
  report.sdk = redactLog(sdk.exit === 0 ? sdk.output : run('flutter', ['--version'], cwd).output);
  report.node = process.version;
  if (!options.baselineOnly) {
    const findings = inspectSecrets(files.map((filename) => ({ filename, patch: git('diff', '--no-ext-diff', '--no-textconv', base, '--', filename) })));
    report.checks.push({ name: 'secret-patterns', status: findings.length ? 'failed' : 'passed', findings });
    await check('diff', 'git', ['diff', '--check', `${base}...${head}`]);
    await check('dart-lint', 'yarn', ['lint:dart']);
    await check('dart-tests', 'yarn', ['test:dart']);
  }
  if (await check('dart-coverage-tests', 'yarn', ['coverage:dart'])) await coverage('dart', scope.dart);
  if (scope.gui) {
    if (!options.baselineOnly) await check('gui-lint', 'yarn', ['lint:flutter']);
    if (await check('gui-coverage-tests', 'node', [fileURLToPath(new URL('./run-dart.js', import.meta.url)), '--flutter', 'test', '--coverage'], join(cwd, 'gui'))) await coverage('gui', true);
  }
  if (!options.baselineOnly && scope.visual) await check('gui-goldens', 'yarn', ['test:flutter:visual']);
  if (scope.docs) {
    await check('translation-parity', 'node', ['scripts/check-translations.mjs']);
    await check('docs-build', 'yarn', ['docs:build']);
    if (files.some((path) => /^website\/src\//.test(path))) await check('website-tests', 'yarn', ['test:website']);
  }
  if (scope.tooling) await check('process-tests', 'yarn', ['test:process']);
  for (const kind of requiredEvidence(scope)) {
    let evidence;
    try { evidence = JSON.parse(await readFile(join(options['evidence-dir'] || '', `${kind}.json`), 'utf8')); } catch { /* Missing evidence remains pending. */ }
    const result = evaluateEvidence(evidence, { ticket: options.ticket, head, kind });
    if (result.status === 'passed') {
      for (const artifact of evidence.artifacts) {
        try {
          const bytes = await readFile(artifact.path);
          if (createHash('sha256').update(bytes).digest('hex') !== artifact.sha256) throw new Error('mismatch');
        } catch { result.status = 'pending'; result.reason = 'Evidence artifact missing or hash mismatch'; }
      }
    }
    report.checks.push({ name: `${kind}-acceptance`, ...result });
  }
  report.status = report.checks.every((check) => check.status === 'passed') ? 'passed' : 'pending_or_failed';
  await writeFile(join(out, 'validation-report.json'), JSON.stringify(report, null, 2) + '\n');
  await writeFile(join(out, 'summary.md'), `# ${options.ticket || 'Baseline'} validation\n\nHead: ${head}\nBase: ${base}\nResult: ${report.status}\n\n${report.checks.map((check) => `- ${check.name}: ${check.status}${check.reason ? ` (${check.reason})` : ''}`).join('\n')}\n`);
  console.log(`Validation ${report.status}: ${out}/validation-report.json`);
  return report.status === 'passed' ? 0 : 1;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
  main().then((code) => { process.exitCode = code; }).catch(() => { console.error('Ticket validation failed; verify options, committed source and baseline.'); process.exitCode = 1; });
}
