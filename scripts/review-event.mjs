import { readFile, appendFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { assertReviewCurrent, cancelReviewRuns, ReviewStopped } from './review-lifecycle.mjs';
import { collectReviewEvidence } from './review-evidence.mjs';
import { updateChecklist } from './review-checklist.mjs';
import { githubRequest } from './github-api.mjs';

export async function handleReviewEvent(event, mode, env = process.env, request = githubRequest) {
  const repository = env.GITHUB_REPOSITORY;
  const number = Number(env.PR_NUMBER || event.pull_request?.number || event.workflow_run?.pull_requests?.[0]?.number);
  if (!Number.isSafeInteger(number) || number <= 0) return;
  if (mode === 'close') {
    try { await assertReviewCurrent(repository, number, undefined, request); }
    catch (error) {
      if (!(error instanceof ReviewStopped)) throw error;
      await cancelReviewRuns(repository, number, request);
    }
    return;
  }
  const expected = event.workflow_run?.head_sha || event.pull_request?.head?.sha || env.REVIEW_EXPECTED_HEAD;
  try {
    const pull = await assertReviewCurrent(repository, number, expected, request);
    if (mode === 'guard') {
      await appendFile(env.GITHUB_OUTPUT, `eligible=true\nnumber=${number}\nhead=${pull.head.sha}\n`);
    } else if (mode === 'enforce') {
      const result = JSON.parse(await readFile(env.REVIEW_RESULT_PATH, 'utf8'));
      if (result.head_sha === pull.head.sha && result.verdict === 'request_changes') process.exitCode = 1;
    } else {
      const evidence = mode === 'evidence' ? await collectReviewEvidence(repository, number, pull.head.sha, request) : undefined;
      let phase = mode === 'checklist' ? 'waiting_ci' : mode === 'progress' ? env.REVIEW_PROGRESS_PHASE : undefined;
      if (phase === 'completed') {
        const result = JSON.parse(await readFile(env.REVIEW_RESULT_PATH, 'utf8'));
        if (result.head_sha !== pull.head.sha && !(result.verdict === 'skip' && !result.head_sha)) {
          throw new ReviewStopped('Review result belongs to another revision');
        }
        if (result.verdict === 'skip') phase = 'skipped';
        else if (result.error || result.llm?.error) phase = 'failed';
      }
      const progress = phase ? {
        phase, run_id: mode === 'checklist' ? 0 : Number(env.GITHUB_RUN_ID),
        run_attempt: Number(env.GITHUB_RUN_ATTEMPT || 1), updated_at: new Date().toISOString(),
        url: mode === 'checklist' ? `https://github.com/${repository}/pull/${number}/checks`
          : `https://github.com/${repository}/actions/runs/${env.GITHUB_RUN_ID}`,
      } : undefined;
      await updateChecklist({ repository, number, head: pull.head.sha, botLogin: env.REVIEW_BOT_LOGIN, evidence, progress, request });
    }
  } catch (error) {
    if (error instanceof ReviewStopped) console.log(error.message);
    else throw error;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  handleReviewEvent(JSON.parse(await readFile(process.env.GITHUB_EVENT_PATH, 'utf8')), process.argv[2])
    .catch((error) => { console.error(error); process.exitCode = 1; });
}
