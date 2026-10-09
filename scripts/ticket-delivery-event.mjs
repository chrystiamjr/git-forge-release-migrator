#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createApi, githubList } from './ticket-pr-api.mjs';
import { issueFromBody } from './ticket-pr-policy.mjs';
import { captureReviewBinding, readHumanDecision } from './ticket-human-review.mjs';
import { syncTicket } from './ticket-pr-sync.mjs';

export function eventNumber(event, repository) {
  if (event.repository?.full_name !== repository) throw new Error('Untrusted delivery event repository');
  if (event.issue && !event.issue.pull_request) return null;
  const number = event.pull_request?.number || event.issue?.number;
  if (!Number.isSafeInteger(number) || number < 1) throw new Error('Invalid PR event number');
  return number;
}

export async function publishCheck(api, config, pull, name, passed, summary) {
  const external = `gfrm-delivery:${pull.number}:${pull.head.sha}:${name}`;
  const prefix = `/repos/${config.repository}`;
  const runs = await githubList(api, `${prefix}/commits/${pull.head.sha}/check-runs`);
  const existing = runs.filter((run) => run.external_id === external && run.app?.slug === 'github-actions');
  if (existing.length > 1) throw new Error('Duplicate owned delivery checks; reconcile');
  const body = {
    name, head_sha: pull.head.sha, external_id: external, status: 'completed', conclusion: passed ? 'success' : 'failure',
    output: { title: passed ? `${name} satisfied` : `${name} pending`, summary },
  };
  if (existing.length) delete body.head_sha;
  await api.gh(`${prefix}/check-runs${existing.length ? `/${existing[0].id}` : ''}`, existing.length ? 'PATCH' : 'POST', body);
}

export async function handleEvent(api, config, event, enabled) {
  const number = eventNumber(event, config.repository);
  if (!number) return { status: 'not_applicable' };
  const observedPull = await api.gh(`/repos/${config.repository}/pulls/${number}`);
  await captureReviewBinding(api, config, observedPull, event);
  const pull = await api.gh(`/repos/${config.repository}/pulls/${number}`);
  const comments = await githubList(api, `/repos/${config.repository}/issues/${number}/comments`);
  const decision = await readHumanDecision(api, config, pull, comments);
  await publishCheck(api, config, pull, 'human-review', !!decision,
    decision ? `Human decision: ${decision.url}\nReviewed head: ${decision.head_sha}`
      : `Maintainer must review current head ${pull.head.sha} and personally post /reviewed (automatic SHA capture) or /reviewed ${pull.head.sha}. Delayed or changed PRs need a new comment or explicit SHA. Bot approval is auxiliary; merge remains manual.`);
  let linked = false;
  let result;
  try {
    const issue = issueFromBody(pull.body, config);
    if (!issue) {
      linked = true;
      result = { status: 'not_applicable', reason: 'Explicit standalone maintenance plan' };
    } else {
      // Verify the association before completion checks so ticket-link can become green.
      const association = await syncTicket(api, config, { action: 'link', number, apply: true, enabled });
      linked = association.status === 'linked';
      await publishCheck(api, config, pull, 'ticket-link', linked,
        linked ? `Verified https://${config.youtrackHost}/issue/${issue} association to ${pull.html_url}`
          : 'Tracker link not verified; owner must enable authorized synchronization credentials.');
      result = await syncTicket(api, config, { action: pull.merged ? 'merge' : 'review', number, apply: true, enabled });
      return result;
    }
  } finally {
    if (!result || result.status === 'not_applicable') {
      await publishCheck(api, config, pull, 'ticket-link', linked,
        linked ? (result?.status === 'not_applicable' ? 'Explicit standalone maintenance plan; no cloud ticket selected.' : 'PR association verified; completion verification remains pending.') : 'Ticket association missing or API verification failed. Delivery remains pending.');
    }
  }
  return result;
}

export async function main() {
  const config = JSON.parse(await readFile(new URL('../.github/ticket-delivery.json', import.meta.url), 'utf8'));
  const event = JSON.parse(await readFile(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const result = await handleEvent(createApi(config), config, event, process.env.ENABLE_YOUTRACK_SYNC === 'true');
  console.log(JSON.stringify(result));
}

if (process.argv[1] && process.argv[1] !== '-' && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
  main().catch(() => { console.error('Delivery event failed; no completion claimed. Reconcile verified metadata/credentials.'); process.exitCode = 1; });
}
