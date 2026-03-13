#!/usr/bin/env node

import { readFile } from 'node:fs/promises';

const REVIEW_RESULT_PATH = process.env.REVIEW_RESULT_PATH || 'review-result.json';
const GH_TOKEN = process.env.GH_TOKEN;
const REPOSITORY = process.env.GITHUB_REPOSITORY;
const PR_NUMBER = Number(process.env.PR_NUMBER);

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

function formatInlineComment(finding, marker) {
  const prefix = finding.severity === 'blocking' ? '[blocking]' : '[note]';
  return `${marker}\n${prefix} ${finding.message}`;
}

async function removePreviousInlineComments(owner, repo, marker) {
  const comments = await paginate(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/comments`);
  const deletableComments = comments.filter((comment) => String(comment.body || '').includes(marker));

  for (const comment of deletableComments) {
    await githubRequest(`/repos/${owner}/${repo}/pulls/comments/${comment.id}`, {
      method: 'DELETE',
    });
  }
}

async function postInlineFinding(owner, repo, headSha, finding, marker) {
  await githubRequest(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/comments`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      body: formatInlineComment(finding, marker),
      commit_id: headSha,
      path: finding.path,
      line: finding.line,
      side: 'RIGHT',
    }),
  });
}

async function submitReview(owner, repo, event, body) {
  await githubRequest(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/reviews`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      event,
      body,
    }),
  });
}

async function loadReviewResult() {
  const raw = await readFile(REVIEW_RESULT_PATH, 'utf8');
  return JSON.parse(raw);
}

async function main() {
  assertRequiredEnv();

  const result = await loadReviewResult();
  const { owner, repo } = parseRepository(REPOSITORY);

  await removePreviousInlineComments(owner, repo, result.marker);

  for (const finding of result.findings) {
    await postInlineFinding(owner, repo, result.head_sha, finding, result.marker);
  }

  if (result.verdict === 'request_changes') {
    await submitReview(
      owner,
      repo,
      'REQUEST_CHANGES',
      `Issues found — see inline comments.\n\n${result.marker}`,
    );
    return;
  }

  if (result.verdict === 'approve') {
    await submitReview(owner, repo, 'APPROVE', `Automated review complete.\n\n${result.marker}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
