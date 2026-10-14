import { githubRequest } from './github-api.mjs';

export class ReviewStopped extends Error {}
const ACTIVE_RUN_STATUSES = ['queued', 'in_progress', 'requested', 'waiting', 'pending'];

export async function assertReviewCurrent(repository, number, head, request = githubRequest) {
  const pull = await request(`/repos/${repository}/pulls/${number}`);
  if (pull.state !== 'open' || pull.merged || (head && pull.head.sha !== head)) {
    throw new ReviewStopped('PR closed, merged, or changed since this review started');
  }
  return pull;
}

// All writes, including fallback writes, pass through the same live-state guard.
export function guardedRequest(repository, number, head, request = githubRequest) {
  return async (path, options = {}) => {
    if (options.method && options.method !== 'GET') await assertReviewCurrent(repository, number, head, request);
    return request(path, options);
  };
}

export async function cancelReviewRuns(repository, number, request = githubRequest) {
  const runIds = new Set();
  for (const workflow of ['auto-pr-review.yml', 'pr-review-lifecycle.yml']) {
    for (const status of ACTIVE_RUN_STATUSES) {
      for (let page = 1; ; page++) {
        const data = await request(`/repos/${repository}/actions/workflows/${workflow}/runs?status=${status}&per_page=100&page=${page}`);
        for (const run of data.workflow_runs) {
          if (run.status === 'completed' || String(run.id) === process.env.GITHUB_RUN_ID) continue;
          // workflow_run records may not carry pull_requests; our run-name provides an explicit PR binding.
          if ((run.pull_requests || []).some((pr) => pr.number === number) || run.display_title === `PR review #${number}`) {
            runIds.add(run.id);
          }
        }
        if (data.workflow_runs.length < 100) break;
      }
    }
  }
  // Finish pagination before cancellations remove entries and shift subsequent pages.
  for (const id of runIds) {
    try { await request(`/repos/${repository}/actions/runs/${id}/cancel`, { method: 'POST' }); }
    catch (error) { if (!String(error.message).includes('409')) throw error; }
  }
}
