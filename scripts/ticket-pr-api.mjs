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

export async function checkStates(api, repository, number) {
  const [owner, name] = repository.split('/');
  const checks = [];
  let cursor = null;
  do {
    const result = await api.gh('/graphql', 'POST', {
      query: `query($owner:String!,$name:String!,$number:Int!,$cursor:String){ repository(owner:$owner,name:$name){ pullRequest(number:$number){ commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100,after:$cursor){pageInfo{hasNextPage,endCursor} nodes{... on CheckRun{name status conclusion startedAt checkSuite{app{slug}}} ... on StatusContext{context state}}}}}}}}}}`,
      variables: { owner, name, number, cursor },
    });
    if (result.errors?.length) throw new Error('Check-state query failed');
    const contexts = result.data?.repository?.pullRequest?.commits?.nodes?.[0]?.commit?.statusCheckRollup?.contexts;
    if (!contexts) return checks;
    for (const row of contexts.nodes) {
      checks.push({ name: row.name || row.context, passed: row.status === 'COMPLETED' && row.conclusion === 'SUCCESS' && row.checkSuite?.app?.slug === 'github-actions', started: row.startedAt });
    }
    cursor = contexts.pageInfo.hasNextPage ? contexts.pageInfo.endCursor : null;
  } while (cursor);
  // Newer failed executions must supersede earlier successful executions.
  const latest = new Map();
  for (const row of checks.sort((a, b) => new Date(a.started || 0) - new Date(b.started || 0))) latest.set(row.name, row);
  return [...latest.values()];
}
