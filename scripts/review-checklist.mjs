import { createHash } from 'node:crypto';
import { classifyChanges } from './validation-scope.mjs';
import { githubRequest, paginate } from './github-api.mjs';
import { assertReviewCurrent, guardedRequest } from './review-lifecycle.mjs';

export const CHECKLIST_MARKER = '<!-- gfrm-required-tests -->';

export function checklistMetadata(body) {
  const match = String(body).match(/<!-- gfrm-test-state:([A-Za-z0-9+/=]+) -->/);
  try { return match ? JSON.parse(Buffer.from(match[1], 'base64').toString()) : {}; } catch { return {}; }
}

export async function readChecklist(repository, number, botLogin, request = githubRequest) {
  if (!botLogin) throw new Error('Checklist requires a verified bot identity');
  const comments = await paginate(`/repos/${repository}/issues/${number}/comments`, request);
  const own = comments.filter((comment) => comment.user?.login === botLogin && comment.body?.includes(CHECKLIST_MARKER));
  if (own.length > 1) throw new Error('Multiple bot test checklists require reconciliation');
  return own[0] ? { ...own[0], metadata: checklistMetadata(own[0].body) } : null;
}

export function requiredChecks(files) {
  const scope = classifyChanges(files);
  const rows = [
    ['dart-lint', 'Dart formatting and analysis'], ['dart-tests', 'Dart test suite'],
    ['dart-coverage', 'Dart coverage floor and applicable baseline comparison'],
    ['process-tests', 'Review and process tests'], ['translation-parity', 'Translation parity'],
    ['gui-goldens', 'Canonical macOS visual tests'],
  ];
  if (scope.gui) rows.push(['gui-lint', 'Flutter formatting and analysis'], ['gui-coverage', 'Flutter tests and coverage']);
  if (scope.docs) rows.push(['docs-build', 'EN/PT-BR documentation build']);
  if (files.some((path) => path.startsWith('website/src/'))) rows.push(['website-tests', 'Website tests']);
  if (scope.native) rows.push(['native-acceptance', 'Native platform acceptance (separate evidence)']);
  if (scope.live) rows.push(['live-acceptance', 'Live-forge acceptance (separate evidence)']);
  return rows.map(([id, description]) => ({ id, description }));
}

export function mergeRequirements(previous, llm) {
  const merged = new Map((previous || []).map((item) => [item.id,
    llm ? { ...item, implementation_verified: false } : item]));
  for (const item of llm?.test_requirements || []) {
    if (!item.id || !item.description || !['dart', 'gui', 'process', 'website', 'manual'].includes(item.suite)) {
      throw new Error('Invalid AI test requirement');
    }
    if (item.applicable === false) {
      if (!item.evidence?.trim()) throw new Error('Withdrawing a scenario requires evidence');
      merged.delete(item.id);
    } else merged.set(item.id, item);
  }
  // Retain compatibility with old results without repeating text in the review body.
  for (const description of llm?.tests_needed || []) {
    if ([...merged.values()].some((item) => item.description === description)) continue;
    const id = `legacy-${createHash('sha256').update(description).digest('hex').slice(0, 16)}`;
    merged.set(id, { id, description, suite: 'manual', implementation_verified: false });
  }
  return [...merged.values()];
}

export function scenarioStatus(requirement, evidence, assessmentHead) {
  const named = evidence.tests || [];
  const matches = named.filter((test) => test.suite === requirement.suite && test.file === requirement.test_file &&
    test.name === requirement.test_name);
  if (assessmentHead === evidence.head && requirement.implementation_verified && requirement.evidence &&
    matches.length && matches.every((test) => test.status === 'passed')) return 'passed';
  return 'pending';
}

function markdownText(value) { return String(value).replace(/[\r\n]+/g, ' ').replace(/<!--/g, '&lt;!--'); }

export function renderChecklist({ head, files, requirements, assessmentHead, evidence = {}, reviewed = false }) {
  const current = evidence.head === head ? evidence : {};
  const checks = current.checks || {};
  const rows = requiredChecks(files).map((row) => ({ ...row, ...(checks[row.id] || { status: 'pending' }) }));
  rows.push(...requirements.map((item) => ({
    id: item.id, description: item.description,
    status: scenarioStatus(item, current, assessmentHead), url: current.url,
  })));
  const body = [CHECKLIST_MARKER, '## Required tests', '', `Current PR head: \`${head}\``, '',
    reviewed ? 'Review-specific scenarios are included below.' : 'Preliminary checklist; review-specific scenarios are pending.', ''];
  for (const row of rows) {
    const passed = row.status === 'passed';
    body.push(`- [${passed ? 'x' : ' '}] ${markdownText(row.description)} — ${row.status}${row.reason ? `: ${markdownText(row.reason)}` : ''}${row.url ? ` ([evidence](${row.url}))` : ''}`);
  }
  if (rows.every((row) => row.status === 'passed') && reviewed) body.push('', 'All listed requirements have passing evidence for this revision.');
  body.push('', 'Native/live acceptance and human approval remain separate from CI.');
  // Full test inventories can exceed GitHub's comment limit. Persist only evidence for listed scenarios.
  const relevantTests = (current.tests || []).filter((test) => requirements.some((item) =>
    item.suite === test.suite && item.test_file === test.file && item.test_name === test.name));
  const metadata = { head, requirements, assessment_head: assessmentHead, reviewed, evidence: { ...current, tests: relevantTests } };
  body.push('', `<!-- gfrm-test-state:${Buffer.from(JSON.stringify(metadata)).toString('base64')} -->`);
  return body.join('\n');
}

// Workflow publication jobs share a per-PR concurrency group; this read/merge/write must run inside it.
export async function updateChecklist({ repository, number, head, botLogin, llm, evidence, request = githubRequest }) {
  await assertReviewCurrent(repository, number, head, request);
  const current = await readChecklist(repository, number, botLogin, request);
  const files = await paginate(`/repos/${repository}/pulls/${number}/files`, request);
  const old = current?.metadata || {};
  const completed = llm && !llm.error && !llm.skipped;
  const sameHead = old.head === head;
  const requirements = mergeRequirements(old.requirements, completed ? llm : null);
  const body = renderChecklist({
    head, files: files.map((file) => file.filename), requirements,
    assessmentHead: completed ? head : sameHead ? old.assessment_head : null,
    reviewed: Boolean(completed || (sameHead && old.reviewed)),
    evidence: evidence || (sameHead ? old.evidence : {}) || {},
  });
  if (current?.body === body) return current.html_url;
  const write = guardedRequest(repository, number, head, request);
  const result = await write(current ? `/repos/${repository}/issues/comments/${current.id}` : `/repos/${repository}/issues/${number}/comments`, {
    method: current ? 'PATCH' : 'POST', body: JSON.stringify({ body }),
  });
  return result.html_url;
}
