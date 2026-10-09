const MAX_COLLECTION_PAGES = 100;

export function createApi(config, env = process.env, fetchImpl = fetch) {
  const github = 'https://api.github.com';
  const youtrack = `https://${config.youtrackHost}`;
  async function request(url, token, method = 'GET', body) {
    if (!token) throw new Error('Required API credential unavailable');
    const response = await fetchImpl(url, {
      method, redirect: 'error', signal: AbortSignal.timeout(20000),
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json', 'Content-Type': 'application/json', 'User-Agent': 'gfrm-ticket-delivery' },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (!response.ok) throw new Error(`API request failed (${response.status})`);
    return response.status === 204 ? null : response.json();
  }
  return {
    gh(path, method, body) {
      if (!path.startsWith('/repos/') && path !== '/graphql') throw new Error('Untrusted GitHub API path');
      return request(github + path, env.GH_TOKEN, method, body);
    },
    yt(path, method, body) {
      if (!/^\/api\/(issues\/GFRM-\d+(?:\/comments(?:\/[^/?]+)?)?|users\/me|commands)(?:\?|$)/.test(path)) throw new Error('Untrusted tracker path');
      return request(youtrack + path, env.YOUTRACK_TOKEN, method, body);
    },
  };
}

export async function githubList(api, path) {
  const rows = [];
  for (let page = 1; page <= MAX_COLLECTION_PAGES; page++) {
    const response = await api.gh(`${path}${path.includes('?') ? '&' : '?'}per_page=100&page=${page}`);
    const entries = Array.isArray(response) ? response : response.check_runs;
    if (!Array.isArray(entries)) throw new Error('Invalid GitHub collection');
    rows.push(...entries);
    if (entries.length < 100) return rows;
  }
  throw new Error('Collection pagination limit reached; no truncated evidence accepted');
}

export async function trackerComments(api, issue) {
  const rows = [];
  for (let skip = 0; skip < MAX_COLLECTION_PAGES * 100; skip += 100) {
    const entries = await api.yt(`/api/issues/${issue}/comments?fields=id,text,deleted,author(id)&$top=100&$skip=${skip}`);
    if (!Array.isArray(entries)) throw new Error('Invalid tracker collection');
    rows.push(...entries.filter((entry) => !entry.deleted));
    if (entries.length < 100) return rows;
  }
  throw new Error('Collection pagination limit reached; no truncated evidence accepted');
}

export async function checkStates(api, repository, number, head) {
  const runs = await githubList(api, `/repos/${repository}/commits/${head}/check-runs?filter=latest`);
  const checks = runs.filter((run) => run.app?.slug === 'github-actions').map((run) => ({
    name: run.name, passed: run.status === 'completed' && run.conclusion === 'success',
  }));
  const [owner, name] = repository.split('/');
  let cursor = null;
  let resolved = true;
  for (let page = 0; page < MAX_COLLECTION_PAGES; page++) {
    const response = await api.gh('/graphql', 'POST', {
      query: `query($owner:String!,$name:String!,$number:Int!,$cursor:String){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100,after:$cursor){nodes{isResolved}pageInfo{hasNextPage endCursor}}}}}`,
      variables: { owner, name, number, cursor },
    });
    const threads = response.data?.repository?.pullRequest?.reviewThreads;
    if (response.errors?.length || !threads) throw new Error('Conversation evidence unavailable');
    resolved = resolved && threads.nodes.every((thread) => thread.isResolved === true);
    if (!threads.pageInfo.hasNextPage) return [...checks, { name: 'resolved-conversations', passed: resolved }];
    cursor = threads.pageInfo.endCursor;
  }
  throw new Error('Conversation evidence exceeds pagination limit');
}
