#!/usr/bin/env node

const GH_TOKEN = process.env.GH_TOKEN;
const REPOSITORY = process.env.GITHUB_REPOSITORY;
const PR_NUMBER = Number(process.env.PR_NUMBER);
const REVIEW_RESULT_PATH = process.env.REVIEW_RESULT_PATH || 'review-result.json';

function assertRequiredEnv() {
  if (!GH_TOKEN) {
    throw new Error('GH_TOKEN is required.');
  }
  if (!REPOSITORY || !REPOSITORY.includes('/')) {
    throw new Error('GITHUB_REPOSITORY must be set as owner/repo.');
  }
  if (!Number.isInteger(PR_NUMBER) || PR_NUMBER <= 0) {
    throw new Error('PR_NUMBER must be a positive integer.');
  }
}

function parseRepository(fullName) {
  const [owner, repo] = fullName.split('/');
  return { owner, repo };
}

async function githubRequest(path, init = {}) {
  const response = await fetch(`https://api.github.com${path}`, {
    ...init,
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${GH_TOKEN}`,
      'User-Agent': 'gfrm-auto-pr-review',
      ...init.headers,
    },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`GitHub API ${response.status} for ${path}: ${body}`);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json();
}

async function githubGraphql(query, variables) {
  const result = await githubRequest('/graphql', {
    method: 'POST',
    body: JSON.stringify({ query, variables }),
    headers: {
      'Content-Type': 'application/json',
    },
  });

  if (result.errors?.length) {
    throw new Error(`GitHub GraphQL error: ${JSON.stringify(result.errors)}`);
  }

  return result.data;
}

async function paginate(path) {
  const items = [];
  let page = 1;

  while (true) {
    const separator = path.includes('?') ? '&' : '?';
    const data = await githubRequest(`${path}${separator}per_page=100&page=${page}`);

    if (!Array.isArray(data) || data.length === 0) {
      break;
    }

    items.push(...data);

    if (data.length < 100) {
      break;
    }

    page += 1;
  }

  return items;
}

export {
  GH_TOKEN,
  REPOSITORY,
  PR_NUMBER,
  REVIEW_RESULT_PATH,
  assertRequiredEnv,
  parseRepository,
  githubRequest,
  githubGraphql,
  paginate,
};
