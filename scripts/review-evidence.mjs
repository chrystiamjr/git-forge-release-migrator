import { execFileSync } from 'node:child_process';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { githubRequest } from './github-api.mjs';

const MAX_ARCHIVE_BYTES = 32 * 1024 * 1024;

export async function readValidationArtifact(repository, runId, request = githubRequest) {
  const artifacts = await request(`/repos/${repository}/actions/runs/${runId}/artifacts?per_page=100`);
  const artifact = artifacts.artifacts.find((item) => item.name === 'ticket-validation-report' && !item.expired);
  if (!artifact || artifact.size_in_bytes > MAX_ARCHIVE_BYTES) return null;
  const directory = await mkdtemp(join(tmpdir(), 'gfrm-review-evidence-'));
  try {
    // gh follows the signed archive redirect without disclosing credentials to PR code.
    const bytes = execFileSync('gh', ['api', `/repos/${repository}/actions/artifacts/${artifact.id}/zip`], {
      maxBuffer: MAX_ARCHIVE_BYTES, timeout: 60_000,
    });
    const archive = join(directory, 'evidence.zip');
    await writeFile(archive, bytes);
    const paths = execFileSync('unzip', ['-Z1', archive], { encoding: 'utf8', maxBuffer: 1024 * 1024, timeout: 10_000 }).split('\n');
    const reports = paths.filter((path) => path.endsWith('/validation-report.json') && !path.includes('/baseline-'));
    if (reports.length !== 1 || !/^[a-zA-Z0-9_./-]+$/.test(reports[0]) || reports[0].split('/').includes('..')) return null;
    // Stream a single bounded JSON entry; never extract arbitrary paths or execute artifact content.
    const raw = execFileSync('unzip', ['-p', archive, reports[0]], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 10_000 });
    return JSON.parse(raw);
  } finally { await rm(directory, { recursive: true, force: true }); }
}

export function evidenceFromRun(run, jobs, report, head, base) {
  const evidence = { head, run_id: run.id, run_attempt: run.run_attempt, url: run.html_url, checks: {}, tests: [] };
  const validReport = report?.schema_version === 1 && !report.baseline && report.pr_head_sha === head &&
    report.pr_base_sha === base && report.base_sha === base && /^[a-f0-9]{40}$/.test(report.head_sha || '');
  if (validReport) {
    for (const check of report.checks || []) evidence.checks[check.name] = {
      status: ['passed', 'failed', 'pending', 'delegated', 'skipped', 'cancelled'].includes(check.status) ? check.status : 'pending',
      reason: check.reason, url: run.html_url,
    };
    evidence.tests = Array.isArray(report.tests) ? report.tests : [];
  }
  for (const job of jobs) {
    if (job.name === 'gui-visual') evidence.checks['gui-goldens'] = {
      status: job.conclusion === 'success' ? validReport ? 'passed' : 'pending' : job.conclusion || 'pending',
      reason: job.conclusion === 'success' && !validReport ? 'Waiting for evidence bound to the current head and base' : undefined,
      url: job.html_url,
    };
    if (job.name !== 'test') continue;
    for (const step of job.steps || []) {
      const key = { 'Check translations parity': 'translation-parity', 'Test process and review helpers': 'process-tests' }[step.name];
      if (key && !evidence.checks[key]) evidence.checks[key] = {
        status: step.conclusion === 'success' ? 'passed' : step.conclusion || 'pending', url: job.html_url,
      };
    }
  }
  return evidence;
}

export async function collectReviewEvidence(repository, number, head, request = githubRequest, readArtifact = readValidationArtifact) {
  const pull = await request(`/repos/${repository}/pulls/${number}`);
  const pending = { head, checks: {}, tests: [] };
  if (pull.state !== 'open' || pull.head.sha !== head) return pending;
  const data = await request(`/repos/${repository}/actions/workflows/quality-checks.yml/runs?event=pull_request&head_sha=${head}&per_page=100`);
  const runs = data.workflow_runs.filter((run) => run.head_sha === head && (run.pull_requests || []).some((pr) => pr.number === number));
  const run = runs.sort((a, b) => b.id - a.id)[0];
  if (!run || run.status !== 'completed') return pending;
  const jobs = [];
  for (let page = 1; ; page++) {
    const result = await request(`/repos/${repository}/actions/runs/${run.id}/attempts/${run.run_attempt}/jobs?per_page=100&page=${page}`);
    jobs.push(...result.jobs);
    if (result.jobs.length < 100) break;
  }
  let report = null;
  try { report = await readArtifact(repository, run.id, request); }
  catch (error) { console.warn(`Validation evidence unavailable: ${error.message}`); }
  // A prior attempt's artifact must never certify a rerun.
  if (String(report?.ci_run_id) !== String(run.id) || Number(report?.ci_run_attempt) !== run.run_attempt) report = null;
  if (report && !/^[a-f0-9]{40}$/.test(report.head_sha || '')) report = null;
  if (report && report.head_sha !== head) {
    const commit = await request(`/repos/${repository}/git/commits/${report.head_sha}`);
    const parents = (commit.parents || []).map((parent) => parent.sha);
    if (!parents.includes(head) || !parents.includes(pull.base.sha) || parents.length !== 2) report = null;
  }
  return evidenceFromRun(run, jobs, report, head, pull.base.sha);
}
