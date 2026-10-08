export function issueFromBody(body, config) {
  const pattern = /https:\/\/[^\s<>()[\]]+\/issue\/[A-Z]+-\d+/g;
  const urls = [...new Set((body || '').match(pattern) || [])];
  if (urls.length === 0 && /^Process plan: LOCAL-[a-z0-9-]+\s*$/m.test(body || '')) return null;
  if (urls.length !== 1) throw new Error('PR requires one unambiguous YouTrack URL or explicit standalone process ID');
  const url = new URL(urls[0]);
  const id = url.pathname.split('/').pop();
  if (url.host !== config.youtrackHost || url.username || url.password || !id.startsWith(`${config.issueProject}-`)) {
    throw new Error('Ticket host/project not allowlisted');
  }
  return id;
}

export function activeHumanDecision(comments, head, humans) {
  if (!/^[a-f0-9]{40}$/.test(head)) return null;
  const decisions = comments.filter((comment) =>
    comment.user?.type === 'User' && humans.includes(comment.user.login) &&
    ['OWNER', 'MEMBER', 'COLLABORATOR'].includes(comment.author_association) &&
    new RegExp(`^/(reviewed|revoke-review) ${head}$`).test((comment.body || '').trim()),
  ).sort((a, b) => new Date(b.updated_at || b.created_at) - new Date(a.updated_at || a.created_at) || b.id - a.id);
  const latest = decisions[0];
  if (!latest || latest.body.trim().startsWith('/revoke-review') || latest.updated_at !== latest.created_at) return null;
  return { login: latest.user.login, comment_id: latest.id, url: latest.html_url, head_sha: head, reviewed_at: latest.created_at };
}

export function canComplete(pull, decision, checks, config) {
  if (!pull.merged || !pull.merged_at || !pull.merge_commit_sha || pull.base?.ref !== 'main') return false;
  if (!decision || decision.head_sha !== pull.head.sha || !config.humanReviewers.includes(decision.login)) return false;
  if (!(Date.parse(decision.reviewed_at) <= Date.parse(pull.merged_at))) return false;
  if (pull.merged_by?.type !== 'User' || !config.humanMergers.includes(pull.merged_by.login)) return false;
  if (!checks.some((check) => check.name === 'resolved-conversations' && check.passed === true)) return false;
  return config.requiredChecks.every((name) => {
    const matches = checks.filter((check) => check.name === name);
    return matches.length > 0 && matches.every((check) => check.passed === true);
  });
}

export function nextState(current, target, config) {
  if (current === target) return { status: 'already' };
  const from = config.stateOrder.indexOf(current);
  const to = config.stateOrder.indexOf(target);
  return from < 0 || to < 0 || to < from
    ? { status: 'skipped', reason: 'Unknown/manual state or backward transition' }
    : { status: 'move', target };
}

export function associationText(pull, issue, status, decision) {
  const marker = `gfrm-pr-link:${pull.base.repo.full_name}:${pull.number}`;
  return `${marker}\n\nPR: ${pull.html_url}\nTicket: ${issue}\nBranch: ${pull.head.ref}\nHead: ${pull.head.sha}\nStatus: ${status}\n${decision ? `Human review: ${decision.url}\n` : ''}${pull.merged ? `Merge: ${pull.merge_commit_sha}\nMerged by: ${pull.merged_by.login}\nMerged at: ${pull.merged_at}\n` : ''}`;
}
