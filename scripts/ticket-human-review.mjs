import { githubList } from './ticket-pr-api.mjs';
import { activeHumanDecision } from './ticket-pr-policy.mjs';

const recordPrefix = (config, pull) => `gfrm-review-binding:${config.repository}:${pull.number}:`;

export async function readReviewBindings(api, config, pull) {
  const runs = await githubList(api, `/repos/${config.repository}/commits/${pull.head.sha}/check-runs?filter=all`);
  const bindings = [];
  for (const run of runs) {
    if (run.app?.slug !== 'github-actions' || run.status !== 'completed' || run.conclusion !== 'success' || run.head_sha !== pull.head.sha) continue;
    if (!run.external_id?.startsWith(recordPrefix(config, pull))) continue;
    let binding;
    try { binding = JSON.parse(run.output?.summary); } catch { continue; }
    if (!binding || typeof binding !== 'object') continue;
    if (!Number.isSafeInteger(binding.comment_id) || binding.comment_id < 1 || binding.head_sha !== pull.head.sha) continue;
    if (run.external_id !== `${recordPrefix(config, pull)}${binding.comment_id}` || run.name !== `human-review-record-${binding.comment_id}`) continue;
    if (!Number.isFinite(Date.parse(binding.recorded_at)) || !Number.isFinite(Date.parse(binding.comment_created_at)) || Date.parse(binding.recorded_at) < Date.parse(binding.comment_created_at)) continue;
    bindings.push(binding);
  }
  return bindings;
}

export async function readHumanDecision(api, config, pull, comments) {
  const bindings = comments.some((comment) => comment.body?.trim() === '/reviewed') ? await readReviewBindings(api, config, pull) : [];
  return activeHumanDecision(comments, pull.head.sha, config.humanReviewers, bindings);
}

export async function captureReviewBinding(api, config, pull, event) {
  const source = event.comment;
  if (event.action !== 'created' || !event.issue?.pull_request || source?.body?.trim() !== '/reviewed') return;
  if (!Number.isSafeInteger(source.id) || source.id < 1) return;
  const comment = await api.gh(`/repos/${config.repository}/issues/comments/${source.id}`);
  if (comment.id !== source.id || comment.issue_url !== `https://api.github.com/repos/${config.repository}/issues/${pull.number}`) return;
  if (comment.body?.trim() !== '/reviewed' || comment.created_at !== source.created_at || comment.updated_at !== source.updated_at) return;
  // This only validates the human identity; it never writes a human command.
  if (!activeHumanDecision([{ ...comment, body: `/reviewed ${pull.head.sha}` }], pull.head.sha, config.humanReviewers)) return;
  if ((await readReviewBindings(api, config, pull)).some((binding) => binding.comment_id === comment.id)) return;
  const fresh = await api.gh(`/repos/${config.repository}/pulls/${pull.number}`);
  // A delayed event must not silently approve a push or other PR change after the comment.
  if (fresh.state !== 'open' || fresh.merged || fresh.head.sha !== pull.head.sha) return;
  if (fresh.base?.repo?.full_name !== config.repository || fresh.base.ref !== 'main') return;
  if (!Number.isFinite(Date.parse(fresh.updated_at)) || !(Date.parse(fresh.updated_at) <= Date.parse(comment.created_at))) return;
  const binding = { comment_id: comment.id, comment_created_at: comment.created_at, head_sha: pull.head.sha, recorded_at: new Date().toISOString() };
  await api.gh(`/repos/${config.repository}/check-runs`, 'POST', {
    name: `human-review-record-${comment.id}`, head_sha: pull.head.sha,
    external_id: `${recordPrefix(config, pull)}${comment.id}`, status: 'completed', conclusion: 'success',
    output: { title: `Human review recorded for ${pull.head.sha}`, summary: JSON.stringify(binding) },
  });
  const matches = (await readReviewBindings(api, config, pull)).filter((row) => row.comment_id === comment.id);
  if (matches.length !== 1) throw new Error('Automatic human review binding not verified');
}
