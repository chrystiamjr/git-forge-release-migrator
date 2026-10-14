import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { githubRequest, PR_NUMBER } from './github-api.mjs';
import { assertReviewCurrent, ReviewStopped } from './review-lifecycle.mjs';

export const AUTO_REVIEW_MARKER = '<!-- auto-pr-review -->';

export function buildFallbackResult(errorMessage, prNumber = PR_NUMBER) {
  return {
    pr_number: prNumber, verdict: 'request_changes', blocking_findings: 1,
    non_blocking_findings: 0, findings: [], error: errorMessage, marker: AUTO_REVIEW_MARKER,
  };
}

// Used before upload and after download: recovery must work even if analysis never started.
export async function ensureReviewResult(env = process.env, request = githubRequest) {
  const number = Number(env.PR_NUMBER);
  const head = env.REVIEW_EXPECTED_HEAD;
  if (!Number.isSafeInteger(number) || number <= 0 || !/^[a-f0-9]{40}$/.test(head || '') ||
      !/^[^/]+\/[^/]+$/.test(env.GITHUB_REPOSITORY || '') || !env.REVIEW_RESULT_PATH) {
    throw new Error('Explicit repository, PR, head, and result path binding required for recovery');
  }
  try {
    const result = JSON.parse(await readFile(env.REVIEW_RESULT_PATH, 'utf8'));
    if (result?.pr_number === number && (result.verdict === 'skip' ||
        (['approve', 'request_changes', 'wait'].includes(result.verdict) && result.head_sha === head))) return result;
  } catch (error) {
    if (error.code !== 'ENOENT' && !(error instanceof SyntaxError)) throw error;
  }
  let result;
  try {
    await assertReviewCurrent(env.GITHUB_REPOSITORY, number, head, request);
    result = { ...buildFallbackResult('Analysis result missing or invalid. Re-run the Automated PR Review workflow.', number),
      head_sha: head, publication_key: `${env.GITHUB_RUN_ID || ''}:${env.GITHUB_RUN_ATTEMPT || '1'}:${head}` };
  } catch (error) {
    if (!(error instanceof ReviewStopped)) throw error;
    result = { pr_number: number, head_sha: head, verdict: 'skip', skip_reason: error.message,
      findings: [], marker: AUTO_REVIEW_MARKER };
  }
  await mkdir(dirname(env.REVIEW_RESULT_PATH), { recursive: true });
  await writeFile(env.REVIEW_RESULT_PATH, `${JSON.stringify(result, null, 2)}\n`);
  return result;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  ensureReviewResult().catch((error) => { console.error(error); process.exitCode = 1; });
}
