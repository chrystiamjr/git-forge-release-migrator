import assert from 'node:assert/strict';
import test from 'node:test';

import {
  isInlineCommentPermissionError,
  isSelfReviewApproveError,
  isSelfReviewRequestChangesError,
  publishReviewResult,
} from './publish-pr-review.mjs';

test('isInlineCommentPermissionError detects personal access token comment rejection', () => {
  assert.equal(
    isInlineCommentPermissionError(
      new Error(
        'GitHub API 403 for /repos/org/repo/pulls/39/comments: {"message":"Resource not accessible by personal access token"}',
      ),
    ),
    true,
  );
  assert.equal(isInlineCommentPermissionError(new Error('GitHub API 403 for /repos/org/repo/issues/39/comments')), false);
});

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

test('publishReviewResult includes finding summary when inline comments are unavailable', async () => {
  const calls = [];

  await publishReviewResult(
    {
      verdict: 'request_changes',
      marker: '<!-- auto-pr-review -->',
      findings: [
        {
          severity: 'blocking',
          message: 'Workflow still checks out main instead of the PR head SHA.',
          path: '.github/workflows/auto-pr-review.yml',
          line: 31,
        },
      ],
    },
    async (event, body) => {
      calls.push({ event, body });
    },
    { inlineCommentsPublished: false },
  );

  assert.deepEqual(
    calls.map((call) => call.event),
    ['REQUEST_CHANGES'],
  );
  assert.match(calls[0].body, /Inline comments could not be published with this token/);
  assert.match(calls[0].body, /auto-pr-review\.yml:31/);
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
