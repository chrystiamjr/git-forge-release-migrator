#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createApi, githubList, trackerComments, checkStates } from './ticket-pr-api.mjs';
import { activeHumanDecision, associationText, canComplete, issueFromBody, nextState } from './ticket-pr-policy.mjs';

export async function upsertAssociation(api, pull, issue, text) {
  const user = await api.yt('/api/users/me?fields=id');
  const marker = `gfrm-pr-link:${pull.base.repo.full_name}:${pull.number}`;
  const matches = (await trackerComments(api, issue)).filter((row) => row.text?.startsWith(`${marker}\n`));
  if (matches.length > 1 || (matches.length && matches[0].author?.id !== user.id)) {
    throw new Error('Association marker collision; reconcile without overwriting other authors');
  }
  const existing = matches[0];
  if (existing?.text !== text) {
    await api.yt(`/api/issues/${issue}/comments${existing ? `/${encodeURIComponent(existing.id)}` : ''}`, 'POST', { text });
  }
  const verified = (await trackerComments(api, issue)).filter((row) => row.text === text && row.author?.id === user.id);
  if (verified.length !== 1) throw new Error('PR association not verified');
  return { status: existing?.text === text ? 'already' : 'linked', comment_id: verified[0].id };
}

export async function transition(api, issue, target, config) {
  const readState = async () => {
    const result = await api.yt(`/api/issues/${issue}?fields=idReadable,customFields(name,value(name))`);
    return result.customFields.find((field) => field.name === config.stateField)?.value?.name;
  };
  const current = await readState();
  const result = nextState(current, target, config);
  if (result.status === 'move') {
    await api.yt('/api/commands', 'POST', { query: `${config.stateField} ${target}`, issues: [{ idReadable: issue }] });
    if (await readState() !== target) throw new Error('Tracker state not verified');
  }
  return { ...result, from: current, to: target };
}

export async function syncTicket(api, config, { action, number, apply = false, enabled = false }) {
  if (!Number.isSafeInteger(number) || number < 1 || !['link', 'review', 'merge'].includes(action)) throw new Error('Invalid delivery action/PR');
  const pull = await api.gh(`/repos/${config.repository}/pulls/${number}`);
  if (pull.base?.repo?.full_name !== config.repository || !/^[a-f0-9]{40}$/.test(pull.head?.sha || '') || pull.base.ref !== 'main') throw new Error('Untrusted repository/head/base');
  const issue = issueFromBody(pull.body, config);
  if (!issue) return { status: 'not_applicable', reason: 'Explicit standalone process plan' };
  const comments = await githubList(api, `/repos/${config.repository}/issues/${number}/comments`);
  const decision = activeHumanDecision(comments, pull.head.sha, config.humanReviewers);
  const checks = action === 'merge' ? await checkStates(api, config.repository, number) : [];
  const complete = action === 'merge' && canComplete(pull, decision, checks, config);
  const status = complete ? 'Done' : pull.state === 'closed' ? 'Closed without completion evidence' : 'Review pending human decision and merge';
  if (!apply || !enabled) return { status: 'dry_run', issue, complete, reason: !enabled ? 'Tracker synchronization opt-in disabled' : undefined };
  // Association is written and verified independently, including already/skipped state transitions.
  const association = await upsertAssociation(api, pull, issue, associationText(pull, issue, status, decision));
  if (action === 'link') return { status: 'linked', issue, association };
  const state = await transition(api, issue, complete ? config.doneState : config.reviewState, config);
  return { status: 'synced', issue, association, state, complete };
}

export async function main(args = process.argv.slice(2)) {
  const action = args[0];
  const number = Number(args[1]);
  if (args.slice(2).some((arg) => arg !== '--apply')) throw new Error('Unknown delivery option');
  const config = JSON.parse(await readFile(new URL('../.github/ticket-delivery.json', import.meta.url), 'utf8'));
  const result = await syncTicket(createApi(config), config, { action, number, apply: args.includes('--apply'), enabled: process.env.ENABLE_YOUTRACK_SYNC === 'true' });
  console.log(JSON.stringify(result));
  return result;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
  main().catch(() => { console.error('Ticket sync failed; credentials, trusted metadata or API verification missing. No completion claimed.'); process.exitCode = 1; });
}
