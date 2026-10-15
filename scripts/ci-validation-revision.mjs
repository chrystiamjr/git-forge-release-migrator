import { execFileSync } from 'node:child_process';
import { appendFile } from 'node:fs/promises';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const SHA = /^[a-f0-9]{40}$/;

export function resolveCiRevision({ revision, parents, expectedHead, expectedRevision }) {
  if (![revision, expectedHead, expectedRevision].every((value) => SHA.test(value || ''))) {
    throw new Error('CI revision requires immutable tested and PR head SHAs');
  }
  if (revision !== expectedRevision) throw new Error('Checkout differs from the workflow event revision');
  if (parents.length !== 2 || !parents.every((value) => SHA.test(value)) ||
      parents[1] !== expectedHead || parents[0] === expectedHead) {
    throw new Error('Tested revision must merge the target base with the expected PR head');
  }
  return { tested_sha: revision, pr_head_sha: expectedHead, pr_base_sha: parents[0] };
}

export function validateCiReportRevision({ base, declaredBase, ...context }) {
  const revision = resolveCiRevision(context);
  if (base !== revision.pr_base_sha || declaredBase !== base) {
    throw new Error('Validation report base differs from the tested merge base');
  }
  return revision;
}

export async function main(env = process.env, cwd = process.cwd()) {
  if (!env.GITHUB_ENV) throw new Error('GITHUB_ENV is required to bind subsequent validation steps');
  const gitEnvironment = { ...env };
  for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR']) delete gitEnvironment[key];
  const [revision, ...parents] = execFileSync('git', ['show', '-s', '--format=%H %P', 'HEAD'], {
    cwd, env: gitEnvironment, encoding: 'utf8',
  }).trim().split(/\s+/);
  const context = resolveCiRevision({ revision, parents, expectedHead: env.CI_PR_HEAD_SHA, expectedRevision: env.GITHUB_SHA });
  await appendFile(env.GITHUB_ENV, `CI_PR_HEAD_SHA=${context.pr_head_sha}\nCI_PR_BASE_SHA=${context.pr_base_sha}\n`);
  console.log(JSON.stringify(context));
  return context;
}

if (process.argv[1] && process.argv[1] !== '-' && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
  main().catch((error) => { console.error(`CI revision binding failed: ${error.message}`); process.exitCode = 1; });
}
