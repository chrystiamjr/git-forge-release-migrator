import assert from 'node:assert/strict';
import test from 'node:test';

import {
  filterAlreadyPublishedFindings,
  isInlineFinding,
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

test('partitionPublishedFindings matches tiered LLM comments with symbol and why lines', () => {
  const marker = '<!-- auto-pr-review -->';
  const finding = {
    tier: 'critical',
    severity: 'blocking',
    path: 'a.dart',
    line: 2,
    symbol: 'run',
    message: 'Null dereference.',
    why: 'Crashes resume.',
  };

  const { alreadyPublishedFindings } = partitionPublishedFindings(
    [finding],
    [{ path: 'a.dart', line: 2, body: `${marker}\n[critical] Null dereference.\n\nSymbol: \`run\`\n\nWhy: Crashes resume.` }],
    marker,
  );

  assert.deepEqual(alreadyPublishedFindings, [finding]);
});

test('isInlineFinding treats only inline:false as summary-only', () => {
  assert.equal(isInlineFinding({}), true);
  assert.equal(isInlineFinding({ inline: true }), true);
  assert.equal(isInlineFinding({ inline: false }), false);
});

test('publishReviewResult renders summary-only findings and LLM sections in the review body', async () => {
  const calls = [];

  await publishReviewResult(
    {
      verdict: 'request_changes',
      marker: '<!-- auto-pr-review -->',
      findings: [
        { rule: 'llm_important', severity: 'blocking', tier: 'important', path: 'a.dart', line: 50, message: 'Outside hunk.', inline: false },
        { rule: 'llm_critical', severity: 'blocking', tier: 'critical', path: 'a.dart', line: 2, message: 'Inline.', inline: true },
      ],
      llm: {
        engine: 'claude',
        model: 'opus',
        model_version: 'claude-opus-5-5',
        effort: 'medium',
        duration_seconds: 61.4,
        cost_usd: 1.234,
        change_summary: 'Adds resume guard.',
        tests_needed: ['resume with empty checkpoint'],
        verdict_reasoning: 'Blocking bug in resume.',
        truncated_files: ['big.dart'],
        omitted_files: [],
        dismissed_hints: [{ rule: 'long_method', path: 'a.dart', reason: 'Generated table, not logic.' }],
        design_notes: [
          { kind: 'duplication', location: 'a.dart:parse', problem: 'Same hunk parser as b.dart.', direction: 'Share one helper.', worth_doing_now: true },
          { kind: 'design', location: 'c.dart', problem: 'Engine knows provider.', direction: 'Inject adapter.', worth_doing_now: false },
        ],
      },
    },
    async (event, body) => {
      calls.push({ event, body });
    },
    { inlineCommentsPublished: true, summarizedFindings: [] },
  );

  const { event, body } = calls[0];
  assert.equal(event, 'REQUEST_CHANGES');
  assert.match(body, /Findings without an inline anchor in the diff:\n- \[important\] Outside hunk\. \(a\.dart:50\)/);
  assert.doesNotMatch(body, /Inline\. \(a\.dart:2\)/);
  assert.match(body, /### Change Summary\nAdds resume guard\./);
  assert.match(body, /### Tests Needed\n- resume with empty checkpoint/);
  assert.match(
    body,
    /### Design Notes\n- \*\*duplication\*\* \(now\) `a\.dart:parse`: Same hunk parser as b\.dart\. → Share one helper\.\n- \*\*design\*\* \(later\) `c\.dart`: Engine knows provider\. → Inject adapter\./,
  );
  assert.match(body, /partial context \(size budget\): `big\.dart`/);
  assert.match(body, /<summary>Dismissed heuristic hints \(1\)<\/summary>\n\n- `long_method` in `a\.dart`: Generated table, not logic\./);
  assert.match(body, /_Reviewed by claude \/ opus \(claude-opus-5-5, effort: medium\) in 61s, est\. cost \$1\.23\._/);
  assert.ok(body.endsWith('<!-- auto-pr-review -->'));
});

test('publishReviewResult reports an unavailable LLM review', async () => {
  const calls = [];

  await publishReviewResult(
    {
      verdict: 'request_changes',
      marker: '<!-- auto-pr-review -->',
      findings: [
        { rule: 'llm_review_unavailable', severity: 'blocking', path: null, line: null, message: 'LLM review could not run.', inline: false },
      ],
      llm: { error: 'Gemini API 503' },
    },
    async (event, body) => {
      calls.push({ event, body });
    },
    { inlineCommentsPublished: true, summarizedFindings: [] },
  );

  assert.match(calls[0].body, /- \[blocking\] LLM review could not run\./);
  assert.match(calls[0].body, /\*\*LLM review:\*\* unavailable \(Gemini API 503\)\./);
});

test('partitionPublishedFindings matches AI findings by path, line, and tier even when wording changes', () => {
  const marker = '<!-- auto-pr-review -->';
  const reworded = {
    tier: 'important',
    severity: 'blocking',
    path: 'a.dart',
    line: 7,
    message: 'Resume skips the failed tag (new wording).',
    why: 'Different why text.',
  };
  const differentTier = { ...reworded, tier: 'suggestion', severity: 'note' };
  const differentLine = { ...reworded, line: 8 };

  const { unpublishedFindings, alreadyPublishedFindings } = partitionPublishedFindings(
    [reworded, differentTier, differentLine],
    [{ path: 'a.dart', line: 7, body: `${marker}\n[important] Resume drops failed tags.\n\nWhy: old wording.` }],
    marker,
  );

  assert.deepEqual(alreadyPublishedFindings, [reworded]);
  assert.deepEqual(unpublishedFindings, [differentTier, differentLine]);
});

test('partitionPublishedFindings keeps exact-text matching for deterministic findings', () => {
  const marker = '<!-- auto-pr-review -->';
  const finding = { severity: 'blocking', path: 'a.dart', line: 7, message: 'New message.' };

  const { unpublishedFindings } = partitionPublishedFindings(
    [finding],
    [{ path: 'a.dart', line: 7, body: `${marker}\n[blocking] Old message.` }],
    marker,
  );

  assert.deepEqual(unpublishedFindings, [finding]);
});

test('publishReviewResult renders a skipped LLM review without a model footer', async () => {
  const calls = [];

  await publishReviewResult(
    {
      verdict: 'approve',
      marker: '<!-- auto-pr-review -->',
      findings: [],
      llm: { skipped: 'AI review disabled. Set repo variable AI_REVIEW_ENABLED=true to enable.' },
    },
    async (event, body) => {
      calls.push({ event, body });
    },
    { inlineCommentsPublished: true, summarizedFindings: [] },
  );

  assert.match(calls[0].body, /\*\*LLM review:\*\* skipped\. AI review disabled\./);
  assert.doesNotMatch(calls[0].body, /Reviewed by/);
});
