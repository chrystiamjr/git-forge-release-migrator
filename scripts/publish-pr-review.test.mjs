import assert from 'node:assert/strict';
import test from 'node:test';

import {
  filterAlreadyPublishedFindings,
  isInlineCommentPermissionError,
  isSelfReviewApproveError,
  isSelfReviewRequestChangesError,
  partitionPublishedFindings,
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

test('publishReviewResult includes deduped finding summary when inline comment already exists', async () => {
  const calls = [];

  await publishReviewResult(
    {
      verdict: 'request_changes',
      marker: '<!-- auto-pr-review -->',
      findings: [
        {
          severity: 'note',
          message: 'Theme, color, or typography definitions changed without test coverage.',
          path: 'gui/lib/src/theme/gfrm_colors.dart',
          line: 1,
        },
      ],
    },
    async (event, body) => {
      calls.push({ event, body });
    },
    {
      inlineCommentsPublished: true,
      summarizedFindings: [
        {
          severity: 'note',
          message: 'Theme, color, or typography definitions changed without test coverage.',
          path: 'gui/lib/src/theme/gfrm_colors.dart',
          line: 1,
        },
      ],
    },
  );

  assert.deepEqual(
    calls.map((call) => call.event),
    ['REQUEST_CHANGES'],
  );
  assert.match(calls[0].body, /summarized findings below/);
  assert.match(calls[0].body, /existing automated inline comments/);
  assert.match(calls[0].body, /gui\/lib\/src\/theme\/gfrm_colors\.dart:1/);
});

test('partitionPublishedFindings separates existing automated inline comments', () => {
  const marker = '<!-- auto-pr-review -->';
  const findings = [
    {
      severity: 'note',
      message: 'Theme, color, or typography definitions changed without test coverage.',
      path: 'gui/lib/src/theme/gfrm_colors.dart',
      line: 1,
    },
    {
      severity: 'blocking',
      message: 'Workflow still checks out main instead of the PR head SHA.',
      path: '.github/workflows/auto-pr-review.yml',
      line: 31,
    },
  ];
  const comments = [
    {
      body: `${marker}\n[note] Theme, color, or typography definitions changed without test coverage.`,
      path: 'gui/lib/src/theme/gfrm_colors.dart',
      line: 1,
    },
  ];

  assert.deepEqual(partitionPublishedFindings(findings, comments, marker), {
    unpublishedFindings: [findings[1]],
    alreadyPublishedFindings: [findings[0]],
  });
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

test('filterAlreadyPublishedFindings skips duplicate automated inline comments', () => {
  const marker = '<!-- auto-pr-review -->';
  const findings = [
    {
      severity: 'note',
      message: 'Theme, color, or typography definitions changed without test coverage.',
      path: 'gui/lib/src/theme/gfrm_colors.dart',
      line: 1,
    },
    {
      severity: 'blocking',
      message: 'Workflow still checks out main instead of the PR head SHA.',
      path: '.github/workflows/auto-pr-review.yml',
      line: 31,
    },
  ];
  const comments = [
    {
      body: `${marker}\n[note] Theme, color, or typography definitions changed without test coverage.`,
      path: 'gui/lib/src/theme/gfrm_colors.dart',
      line: 1,
    },
  ];

  assert.deepEqual(filterAlreadyPublishedFindings(findings, comments, marker), [findings[1]]);
});
