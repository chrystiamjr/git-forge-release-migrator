#!/usr/bin/env node
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { buildReviewContext, buildUserPrompt, callClaudeCode, routeClaudeReview, REVIEW_SCHEMA,
  normalizeFindings, DISK_IO } from './ai-review.mjs';
import { boundedProcess, isolatedReview, prepareSnapshot, REVIEW_CLI_VERSION } from './review-runner.mjs';
import { verifyReview } from './review-verification.mjs';
import { buildRiskSummary, effortlessConfiguration, ROUTING_ARMS, EFFORTLESS_REVISION } from './review-effortless.mjs';

const DEFAULT_CORPUS = fileURLToPath(new URL('../docs/engineering/review-benchmark/cases.json', import.meta.url));
const PROMPT = fileURLToPath(new URL('./ai-review-prompt.md', import.meta.url));
const COMPATIBILITY = new URL('../docs/engineering/review-benchmark/compatibility.json', import.meta.url);

async function assertPluginCompatibility() {
  const result = JSON.parse(await readFile(COMPATIBILITY, 'utf8'));
  if (result.plugin_revision !== EFFORTLESS_REVISION || result.cli_version !== REVIEW_CLI_VERSION
      || result.static_validation !== 'passed') throw new Error('Pinned plugin compatibility has not passed; retain current routing');
}

export function validateCorpus(corpus) {
  if (corpus.schema_version !== 1 || corpus.cases?.length !== 12 || !corpus.confirmed_by?.trim()) {
    throw new Error('Twelve cases and human-confirmed labels are required before model trials');
  }
  const ids = new Set();
  for (const item of corpus.cases) {
    if (ids.has(item.id) || !['false_positive', 'real_bug', 'clean'].includes(item.confirmed_label)
        || !/^[a-f0-9]{40}$/.test(item.head_sha) || !/^[a-f0-9]{40}$/.test(item.base_sha)) {
      throw new Error('Invalid or unconfirmed benchmark case');
    }
    ids.add(item.id);
  }
  if (new Set(corpus.cases.map((item) => item.confirmed_label)).size !== 3) {
    throw new Error('Corpus must include false positives, real bugs and clean controls');
  }
}

export function benchmarkPrompt(context, files, item) {
  // Deliberately exclude historical review claims, proposed labels, rationale, later replies and current PR body.
  return buildRiskSummary(files) + buildUserPrompt(context, [], { title: `Review PR #${item.pr} at the supplied revision`, body: '' }, [])
    + '\n<prior_test_requirements>\n[]\n</prior_test_requirements>';
}

async function compareFiles(item) {
  const result = await boundedProcess('gh', ['api', `/repos/${item.repository}/compare/${item.base_sha}...${item.head_sha}`], {
    signal: AbortSignal.timeout(60_000),
  });
  if (result.exitCode !== 0) throw new Error('Cannot retrieve frozen comparison');
  const comparison = JSON.parse(String(result.stdout));
  if (!comparison.files || comparison.files.length >= 300 || comparison.merge_base_commit?.sha !== item.base_sha) {
    throw new Error('Comparison truncated or base is not the immutable merge base');
  }
  return comparison.files;
}

async function benchmarkContext(item) {
  const root = await mkdtemp(join(tmpdir(), 'gfrm-bench-source-'));
  try {
    const [files, source] = await Promise.all([compareFiles(item), prepareSnapshot({ ...item,
      head: item.head_sha, root, signal: AbortSignal.timeout(60_000) })]);
    const context = await buildReviewContext(files, { ...DISK_IO,
      readChangedFile: (file) => readFile(join(source, file.filename), 'utf8').catch(() => null),
    });
    return { files, context, input: benchmarkPrompt(context, files, item) };
  } finally { await rm(root, { recursive: true, force: true }); }
}

export async function runBenchmarkCase(item, arm, directory, env = process.env) {
  if (!ROUTING_ARMS.includes(arm)) throw new Error('Unknown routing arm');
  if (arm !== 'current') await assertPluginCompatibility();
  const { files, context, input } = await benchmarkContext(item);
  const pr = { repository: item.repository, head_sha: item.head_sha, base_sha: item.base_sha };
  const started = Date.now();
  const calls = [];
  const runCommand = async (args, text) => {
    const flag = (name) => args[args.indexOf(name) + 1];
    const result = await isolatedReview({ ...pr, head: item.head_sha, env, input: text,
      system: flag('--system-prompt'), schema: JSON.parse(flag('--json-schema')),
      model: flag('--model'), effort: flag('--effort'), fileTools: false, timeoutMs: 600_000 });
    calls.push(result);
    return { exitCode: 0, stderr: '', stdout: JSON.stringify({ subtype: 'success', structured_output: result.output,
      total_cost_usd: result.cost_usd, modelUsage: result.model_usage }) };
  };
  const corpusKey = createHash('sha256').update(input + await readFile(PROMPT, 'utf8') + REVIEW_CLI_VERSION).digest('hex');
  const cache = join(directory, `detector-${item.head_sha}-${corpusKey}.json`);
  let baseline;
  try { baseline = JSON.parse(await readFile(cache, 'utf8')); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (!baseline) {
    const settings = await routeClaudeReview({ context, pr: { title: `PR #${item.pr}`, body: '' }, runCommand });
    const detected = await callClaudeCode({ ...settings, systemInstruction: await readFile(PROMPT, 'utf8'),
      userText: input, runCommand });
    baseline = { settings, detected, calls };
    await writeFile(cache, JSON.stringify(baseline, null, 2) + '\n', { flag: 'wx' });
  }
  let detected = baseline.detected.review;
  let trial;
  if (arm !== 'current') {
    trial = await isolatedReview({ ...pr, head: item.head_sha, env, input, schema: REVIEW_SCHEMA,
      system: await readFile(PROMPT, 'utf8'), fileTools: false, timeoutMs: 600_000,
      // Effort-only holds baseline model constant; model routing starts at Opus, the plugin's upper bound.
      model: arm === 'effortless-model' ? 'opus' : baseline.settings.model, effort: baseline.settings.effort,
      configure: effortlessConfiguration(arm) });
    detected = trial.output;
  }
  const verified = await verifyReview({ review: detected, pr, priorComments: [], mode: 'enforce', env });
  const report = { schema_version: 1, case_id: item.id, arm, ...pr, input_sha256: corpusKey,
    cli_version: REVIEW_CLI_VERSION, plugin_revision: arm === 'current' ? null : EFFORTLESS_REVISION,
    baseline, trial, detector_findings: normalizeFindings(detected, files),
    candidate_findings: normalizeFindings(verified.review, files), verification: verified.verification,
    duration_seconds: (Date.now() - started) / 1000,
    // Human maps returned findings to the labeled concern; no wording-based automatic truth matching.
    adjudication: { confirmed_by: null, baseline_detected: null, candidate_detected: null,
      baseline_finding_ids: [], candidate_finding_ids: [] } };
  await writeFile(join(directory, `${item.id}-${arm}.json`), JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  return report;
}

export function scoreBenchmark(corpus, reports) {
  validateCorpus(corpus);
  const pending = [];
  let falsePositives = 0, suppressed = 0, missedBugs = 0, newFalsePositives = 0, baselineBugs = 0;
  const ids = new Set();
  for (const item of corpus.cases) {
    const matches = reports.filter((report) => report.case_id === item.id);
    const report = matches[0];
    const label = item.confirmed_label;
    const judged = report?.adjudication;
    if (matches.length !== 1 || report.head_sha !== item.head_sha || report.base_sha !== item.base_sha
        || report.verification?.status !== 'complete' || !judged?.confirmed_by?.trim()
        || typeof judged.baseline_detected !== 'boolean' || typeof judged.candidate_detected !== 'boolean') {
      pending.push(item.id); continue;
    }
    ids.add(report.arm);
    if (label === 'real_bug' && judged.baseline_detected) {
      baselineBugs += 1;
      if (!judged.candidate_detected) missedBugs += 1;
    }
    if (label !== 'real_bug') {
      if (judged.baseline_detected) { falsePositives += 1; if (!judged.candidate_detected) suppressed += 1; }
      else if (judged.candidate_detected) newFalsePositives += 1;
    }
  }
  return { status: pending.length || ids.size !== 1 ? 'pending'
    : falsePositives > 0 && baselineBugs > 0 && suppressed / falsePositives >= 0.5 && !missedBugs && !newFalsePositives ? 'passed' : 'failed',
  pending, false_positives: falsePositives, suppressed, missed_bugs: missedBugs, new_false_positives: newFalsePositives,
  routing_usage_gate: reports.every((report) => report.arm === 'current' || report.trial?.usage_complete === true)
    ? 'requires paired latency/usage comparison and repeated marginal results' : 'pending complete judge usage',
  rollout: 'Requires five real PRs in shadow and human evidence review; never automatically enables enforcement.' };
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  const value = (name) => { const index = args.indexOf(name); return index < 0 ? undefined : args[index + 1]; };
  const corpus = JSON.parse(await readFile(value('--corpus') || DEFAULT_CORPUS, 'utf8'));
  if (command === 'check') {
    const problems = [];
    try { validateCorpus(corpus); } catch (error) { problems.push(error.message); }
    if (!process.env.CLAUDE_CODE_OAUTH_TOKEN) problems.push('Subscription OAuth token unavailable');
    if ((value('--arm') || 'current') !== 'current') {
      try { await assertPluginCompatibility(); } catch (error) { problems.push(error.message); }
    }
    console.log(JSON.stringify({ status: problems.length ? 'pending' : 'ready', problems,
      cli_version: REVIEW_CLI_VERSION, plugin_revision: EFFORTLESS_REVISION }, null, 2));
    return;
  }
  validateCorpus(corpus);
  if (!value('--out')) throw new Error('--out is required; use a private directory outside the repository');
  const out = resolve(value('--out'));
  await mkdir(out, { recursive: true });
  const arm = value('--arm') || 'current';
  if (command === 'run') {
    if (!process.env.CLAUDE_CODE_OAUTH_TOKEN) throw new Error('Subscription OAuth token unavailable');
    const item = corpus.cases.find((entry) => entry.id === value('--case'));
    if (!item) throw new Error('--case must name one confirmed case');
    try { await runBenchmarkCase(item, arm, out); } catch (error) {
      await writeFile(join(out, `${item.id}-${arm}-failure.json`), JSON.stringify({
        case_id: item.id, arm, head_sha: item.head_sha, base_sha: item.base_sha,
        status: 'incomplete', reason: error.message, cli_version: REVIEW_CLI_VERSION,
        plugin_revision: arm === 'current' ? null : EFFORTLESS_REVISION,
      }, null, 2) + '\n', { flag: 'wx' });
      throw error;
    }
  } else if (command === 'score') {
    const reports = await Promise.all(corpus.cases.map((item) => readFile(join(out, `${item.id}-${arm}.json`), 'utf8')
      .then(JSON.parse).catch((error) => { if (error.code === 'ENOENT') return null; throw error; })));
    console.log(JSON.stringify(scoreBenchmark(corpus, reports.filter(Boolean)), null, 2));
  } else throw new Error('Use check, run --case case-01, or score; --arm current|effortless-effort|effortless-model');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
