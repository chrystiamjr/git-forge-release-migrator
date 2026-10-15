import { readFile, appendFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { assertReviewCurrent, cancelReviewRuns, ReviewStopped } from './review-lifecycle.mjs';
import { collectReviewEvidence } from './review-evidence.mjs';
import { updateChecklist } from './review-checklist.mjs';

export async function handleReviewEvent(event, mode, env = process.env) {
  const repository = env.GITHUB_REPOSITORY;
  const number = Number(env.PR_NUMBER || event.pull_request?.number || event.workflow_run?.pull_requests?.[0]?.number);
  if (!Number.isSafeInteger(number) || number <= 0) return;
  if (mode === 'close') {
    try { await assertReviewCurrent(repository, number); }
    catch (error) {
      if (!(error instanceof ReviewStopped)) throw error;
      await cancelReviewRuns(repository, number);
    }
    return;
  }
  const expected = event.workflow_run?.head_sha || event.pull_request?.head?.sha;
  try {
    const pull = await assertReviewCurrent(repository, number, expected);
    if (mode === 'guard') {
      await appendFile(env.GITHUB_OUTPUT, `eligible=true\nnumber=${number}\nhead=${pull.head.sha}\n`);
    } else if (mode === 'enforce') {
      const result = JSON.parse(await readFile(env.REVIEW_RESULT_PATH, 'utf8'));
      if (result.head_sha === pull.head.sha && result.verdict === 'request_changes') process.exitCode = 1;
    } else {
      const evidence = mode === 'evidence' ? await collectReviewEvidence(repository, number, pull.head.sha) : undefined;
      await updateChecklist({ repository, number, head: pull.head.sha, botLogin: env.REVIEW_BOT_LOGIN, evidence });
    }
  } catch (error) {
    if (!(error instanceof ReviewStopped)) throw error;
    console.log(error.message);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  handleReviewEvent(JSON.parse(await readFile(process.env.GITHUB_EVENT_PATH, 'utf8')), process.argv[2])
    .catch((error) => { console.error(error); process.exitCode = 1; });
}
