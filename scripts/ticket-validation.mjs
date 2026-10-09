import { buildSecretFindings } from './review-pr.mjs';

export function classifyChanges(files) {
  return {
    dart: files.some((path) => /^dart_cli\/(lib|bin)\//.test(path)),
    gui: files.some((path) => /^gui\//.test(path) || /^dart_cli\/lib\//.test(path)),
    visual: files.some((path) => (/^gui\/lib\/src\/(features|core\/widgets|theme|app)\//.test(path) || /^gui\/test\/(visual|goldens)\//.test(path))),
    docs: files.some((path) => /^(website\/|README.md$|package.json$|yarn.lock$)/.test(path)),
    tooling: files.some((path) => /^(scripts\/|\.github\/|\.husky\/|package.json$)/.test(path)),
    native: files.some((path) => /^gui\/(macos|windows|linux)\//.test(path)),
    live: files.some((path) => /^dart_cli\/lib\/src\/providers\/(github|gitlab|bitbucket)\.dart$/.test(path)),
  };
}

export function readCoverage(lcov) {
  let covered = 0;
  let lines = 0;
  for (const record of lcov.split('end_of_record')) {
    const source = record.match(/^SF:(.+)$/m)?.[1]?.replaceAll('\\', '/');
    if (!source || !/(^|\/)lib\//.test(source) || /\.g\.dart$/.test(source)) continue;
    for (const match of record.matchAll(/^DA:\d+,(\d+)(?:,.*)?$/gm)) {
      lines++;
      if (Number(match[1]) > 0) covered++;
    }
  }
  if (!lines) throw new Error('No production lines in coverage report');
  return { covered, lines, percent: (covered / lines) * 100 };
}

export function coverageResult(current, baseline, required) {
  if (current.percent < 80) return { status: 'failed', reason: 'Coverage below 80%' };
  if (required && !baseline) return { status: 'pending', reason: 'Comparable base coverage required' };
  if (baseline && current.percent + 1e-9 < baseline.percent) {
    return { status: 'failed', reason: 'Coverage regressed from base' };
  }
  return { status: 'passed' };
}

export function inspectSecrets(files) {
  return buildSecretFindings(files).map(({ path, line, rule }) => ({ path, line, rule }));
}

export function redactLog(output, environment = process.env) {
  let text = output;
  for (const [name, value] of Object.entries(environment)) {
    if (/(TOKEN|PASSWORD|SECRET|(?:ACCESS|API|PRIVATE)_KEY)/i.test(name) && value?.length >= 8) {
      text = text.replaceAll(value, '[REDACTED]');
    }
  }
  // Pattern detection also protects secrets not represented in the environment.
  return text.replace(/\b(?:github_pat_|gh[pousr]_|glpat-|xox[baprs]-)[\w-]+\b/g, '[REDACTED]')
    .replace(/\b(?:AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35})\b/g, '[REDACTED]')
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, '[REDACTED]');
}

export function requiredEvidence(scope) {
  return ['native', 'live'].filter((kind) => scope[kind]);
}

export function evaluateEvidence(evidence, { ticket, head, kind, ciCore = false }) {
  // CI cannot run a native or live-forge scenario; like GUI goldens it delegates, and passed_core is not final delivery.
  if (ciCore) {
    return { status: 'delegated', reason: `Requires local ${kind} acceptance evidence; this is not final delivery verification` };
  }
  if (!evidence || evidence.ticket !== ticket || evidence.head_sha !== head || evidence.kind !== kind) {
    return { status: 'pending', reason: `Missing matching ${kind} evidence` };
  }
  if (evidence.status !== 'passed' || !evidence.artifacts?.length) {
    return { status: 'pending', reason: `Incomplete ${kind} evidence` };
  }
  return { status: 'passed' };
}
