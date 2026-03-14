import assert from 'node:assert/strict';
import test from 'node:test';

import {
  isSelfReviewApproveError,
  isSelfReviewRequestChangesError,
  publishReviewResult,
} from './publish-pr-review.mjs';

test('isSelfReviewApproveError detects self-approval rejection', () => {
  assert.equal(
    isSelfReviewApproveError(
      new Error('GitHub API 422 for /reviews: {"errors":["Review Can not approve your own pull request"]}'),
    ),
    true,
  );
  assert.equal(isSelfReviewApproveError(new Error('GitHub API 422 for /reviews: unrelated')), false);
});

test('isSelfReviewRequestChangesError detects self request-changes rejection', () => {
  assert.equal(
    isSelfReviewRequestChangesError(
      new Error('GitHub API 422 for /reviews: {"errors":["Review Can not request changes on your own pull request"]}'),
    ),
    true,
  );
  assert.equal(isSelfReviewRequestChangesError(new Error('GitHub API 422 for /reviews: unrelated')), false);
});

test('publishReviewResult falls back to comment when self-approval is rejected', async () => {
  const calls = [];

  await publishReviewResult(
    {
      verdict: 'approve',
      marker: '<!-- auto-pr-review -->',
    },
    async (event, body) => {
      calls.push({ event, body });
      if (event === 'APPROVE') {
        throw new Error('GitHub API 422 for /reviews: {"errors":["Review Can not approve your own pull request"]}');
      }
    },
  );

  assert.deepEqual(
    calls.map((call) => call.event),
    ['APPROVE', 'COMMENT'],
  );
  assert.match(calls[1].body, /GitHub rejected a formal approval/);
});

test('publishReviewResult falls back to comment when self request-changes is rejected', async () => {
  const calls = [];

  await publishReviewResult(
    {
      verdict: 'request_changes',
      marker: '<!-- auto-pr-review -->',
    },
    async (event, body) => {
      calls.push({ event, body });
      if (event === 'REQUEST_CHANGES') {
        throw new Error(
          'GitHub API 422 for /reviews: {"errors":["Review Can not request changes on your own pull request"]}',
        );
      }
    },
  );

  assert.deepEqual(
    calls.map((call) => call.event),
    ['REQUEST_CHANGES', 'COMMENT'],
  );
  assert.match(calls[1].body, /formal request-changes review/);
});

test('publishReviewResult rethrows unrelated approval failures', async () => {
  await assert.rejects(
    publishReviewResult(
      {
        verdict: 'approve',
        marker: '<!-- auto-pr-review -->',
      },
      async () => {
        throw new Error('GitHub API 500 for /reviews: server exploded');
      },
    ),
    /server exploded/,
  );
});
