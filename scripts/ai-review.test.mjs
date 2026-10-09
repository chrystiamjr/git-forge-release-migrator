import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildClaudeChildEnv,
  buildReviewContext,
  buildUserPrompt,
  callClaudeCode,
  callGemini,
  globToRegex,
  normalizeFindings,
  parseApplyTo,
  parseRightSideLines,
  REVIEW_SCHEMA,
  runAiReview,
  toGeminiSchema,
} from './ai-review.mjs';

function buildIo(repoFiles = {}) {
  return {
    readRepoFile: async (path) => repoFiles[path] ?? null,
    readChangedFile: async (file) => repoFiles[file.filename] ?? null,
    listInstructionPaths: async () => Object.keys(repoFiles).filter((path) => path.endsWith('.instructions.md')),
  };
}

function buildGeminiResponse(review, { modelVersion = 'gemini-3.8-flash', status = 200 } = {}) {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => JSON.stringify(review),
    json: async () => ({
      modelVersion,
      candidates: [
        {
          finishReason: 'STOP',
          content: { parts: [{ text: 'thinking...', thought: true }, { text: JSON.stringify(review) }] },
        },
      ],
    }),
  };
}

const EMPTY_REVIEW = {
  change_summary: 'Adds a helper.',
  findings: [],
  design_notes: [],
  dismissed_hints: [],
  tests_needed: [],
  verdict_reasoning: 'Safe.',
};

const noSleep = async () => {};

test('globToRegex matches applyTo globs', () => {
  assert.equal(globToRegex('dart_cli/lib/**/*.dart').test('dart_cli/lib/src/cli.dart'), true);
  assert.equal(globToRegex('dart_cli/lib/**/*.dart').test('dart_cli/lib/cli.dart'), true);
  assert.equal(globToRegex('dart_cli/lib/**/*.dart').test('gui/lib/main.dart'), false);
  assert.equal(globToRegex('scripts/review-pr*.mjs').test('scripts/review-pr.test.mjs'), true);
  assert.equal(globToRegex('scripts/review-pr*.mjs').test('scripts/nested/review-pr.mjs'), false);
  assert.equal(globToRegex('website/**/*').test('website/docs/intro.md'), true);
});

test('parseApplyTo reads frontmatter globs and ignores files without applyTo', () => {
  assert.deepEqual(parseApplyTo('---\napplyTo: "a/**/*.dart,b/*.md"\n---\n# Rules'), ['a/**/*.dart', 'b/*.md']);
  assert.deepEqual(parseApplyTo('# Caveman rules\nno frontmatter'), []);
});

test('buildReviewContext skips generated and removed files and selects guidance by applyTo', async () => {
  const io = buildIo({
    'AGENTS.md': 'agents',
    '.github/instructions/dart-review.instructions.md': '---\napplyTo: "dart_cli/lib/**/*.dart"\n---\ndart rules',
    '.github/instructions/flutter-review.instructions.md': '---\napplyTo: "gui/lib/**/*.dart"\n---\nflutter rules',
    '.github/instructions/caveman.instructions.md': '# no applyTo',
    'dart_cli/lib/src/cli.dart': 'void main() {}\n',
  });

  const context = await buildReviewContext(
    [
      { filename: 'dart_cli/lib/src/cli.dart', status: 'modified', patch: '@@ -1 +1 @@\n+void main() {}' },
      { filename: 'dart_cli/lib/src/model.g.dart', status: 'modified', patch: '@@ -1 +1 @@\n+x' },
      { filename: 'yarn.lock', status: 'modified', patch: '@@ -1 +1 @@\n+x' },
      { filename: 'dart_cli/lib/src/old.dart', status: 'removed', patch: '' },
    ],
    io,
  );

  assert.deepEqual(
    context.guidance.map((entry) => entry.path),
    ['AGENTS.md', '.github/instructions/dart-review.instructions.md'],
  );
  assert.deepEqual(context.files.map((file) => file.path), ['dart_cli/lib/src/cli.dart']);
  assert.match(context.files[0].content, /^ {4}1 \| void main\(\) \{\}/);
});

test('buildReviewContext drops full content for files that exceed the budget', async () => {
  const huge = 'x'.repeat(700_000);
  const io = buildIo({ 'small.dart': 'small', 'huge.dart': huge });

  const context = await buildReviewContext(
    [
      { filename: 'huge.dart', status: 'modified', patch: '@@ -1 +1 @@\n+x' },
      { filename: 'small.dart', status: 'modified', patch: '@@ -1 +1 @@\n+small' },
    ],
    io,
  );

  assert.deepEqual(context.truncatedFiles, ['huge.dart']);
  assert.deepEqual(context.omittedFiles, []);
  assert.deepEqual(context.files.map((file) => file.path), ['huge.dart', 'small.dart']);
  assert.equal(context.files[0].content, null);
  assert.notEqual(context.files[1].content, null);
});

test('buildUserPrompt marks truncated files and lists hints', () => {
  const prompt = buildUserPrompt(
    {
      guidance: [],
      files: [{ path: 'a.dart', status: 'modified', patch: '+x', content: null, truncated: true }],
      truncatedFiles: ['a.dart'],
      omittedFiles: ['b.dart'],
    },
    [{ rule: 'long_method', path: 'a.dart', line: 3, message: 'too long' }],
    { title: 'feat: x', body: null },
  );

  assert.match(prompt, /<changed_file path="a.dart" status="modified" truncated="true">/);
  assert.match(prompt, /- \[long_method\] a\.dart:3 — too long/);
  assert.match(prompt, /<omitted_files>\nb\.dart\n<\/omitted_files>/);
});

test('parseRightSideLines includes added and context lines, not removed lines', () => {
  const lines = parseRightSideLines('@@ -10,3 +20,3 @@\n context\n-removed\n+added\n context2');
  assert.deepEqual([...lines], [20, 21, 22]);
});

test('normalizeFindings maps tiers, drops non-blocking unknown paths, and flags out-of-hunk lines', () => {
  const files = [{ filename: 'a.dart', patch: '@@ -1,2 +1,3 @@\n line1\n+line2\n line3' }];
  const findings = normalizeFindings(
    {
      findings: [
        { tier: 'critical', path: 'a.dart', line: 2, symbol: 'run', message: 'bug', why: 'breaks' },
        { tier: 'important', path: 'a.dart', line: 50, symbol: '', message: 'outside', why: 'w' },
        { tier: 'suggestion', path: 'a.dart', line: 3, symbol: '', message: 'nit', why: 'w' },
        { tier: 'question', path: 'not-in-pr.dart', line: 1, symbol: '', message: 'ghost', why: 'w' },
      ],
    },
    files,
  );

  assert.deepEqual(
    findings.map(({ rule, severity, line, inline }) => ({ rule, severity, line, inline })),
    [
      { rule: 'llm_critical', severity: 'blocking', line: 2, inline: true },
      { rule: 'llm_important', severity: 'blocking', line: 50, inline: false },
      { rule: 'llm_suggestion', severity: 'note', line: 3, inline: true },
    ],
  );
});

test('normalizeFindings caps inline findings at 20', () => {
  const patch = `@@ -0,0 +1,30 @@\n${Array.from({ length: 30 }, (_, index) => `+line${index}`).join('\n')}`;
  const findings = normalizeFindings(
    {
      findings: Array.from({ length: 25 }, (_, index) => ({
        tier: 'suggestion',
        path: 'a.dart',
        line: index + 1,
        symbol: '',
        message: `m${index}`,
        why: 'w',
      })),
    },
    [{ filename: 'a.dart', patch }],
  );

  assert.equal(findings.filter((finding) => finding.inline).length, 20);
  assert.equal(findings.filter((finding) => !finding.inline).length, 5);
});

test('callGemini sends thinking level and schema, skips thought parts, and reports modelVersion', async () => {
  let request;
  const result = await callGemini({
    apiKey: 'test-key',
    model: 'gemini-flash-latest',
    thinkingLevel: 'high',
    systemInstruction: 'system',
    userText: 'user',
    fetchImpl: async (url, init) => {
      request = { url, init };
      return buildGeminiResponse(EMPTY_REVIEW);
    },
    sleep: noSleep,
  });

  const body = JSON.parse(request.init.body);
  assert.match(request.url, /\/models\/gemini-flash-latest:generateContent$/);
  assert.equal(request.init.headers['x-goog-api-key'], 'test-key');
  assert.equal(body.generationConfig.thinkingConfig.thinkingLevel, 'high');
  assert.equal(body.generationConfig.responseMimeType, 'application/json');
  assert.deepEqual(result, { review: EMPTY_REVIEW, modelVersion: 'gemini-3.8-flash', costUsd: null });
});

test('callGemini retries retryable statuses with exponential backoff, then throws', async () => {
  let calls = 0;
  const delays = [];
  await assert.rejects(
    callGemini({
      apiKey: 'k',
      model: 'm',
      thinkingLevel: 'high',
      systemInstruction: 's',
      userText: 'u',
      fetchImpl: async () => {
        calls += 1;
        return { ok: false, status: 503, text: async () => 'overloaded' };
      },
      sleep: async (milliseconds) => {
        delays.push(milliseconds);
      },
    }),
    /Gemini API 503 for model m after 4 attempts: overloaded/,
  );
  assert.equal(calls, 4);
  assert.deepEqual(delays, [2_000, 4_000, 8_000]);
});

test('callGemini succeeds when a retry recovers from a transient 503', async () => {
  let calls = 0;
  const result = await callGemini({
    apiKey: 'k',
    model: 'm',
    thinkingLevel: 'high',
    systemInstruction: 's',
    userText: 'u',
    fetchImpl: async () => {
      calls += 1;
      return calls === 1 ? { ok: false, status: 503, text: async () => 'overloaded' } : buildGeminiResponse(EMPTY_REVIEW);
    },
    sleep: noSleep,
  });

  assert.equal(calls, 2);
  assert.deepEqual(result.review, EMPTY_REVIEW);
});

test('callGemini does not retry non-retryable statuses', async () => {
  let calls = 0;
  await assert.rejects(
    callGemini({
      apiKey: 'k',
      model: 'm',
      thinkingLevel: 'high',
      systemInstruction: 's',
      userText: 'u',
      fetchImpl: async () => {
        calls += 1;
        return { ok: false, status: 400, text: async () => 'bad request' };
      },
      sleep: noSleep,
    }),
    /Gemini API 400/,
  );
  assert.equal(calls, 1);
});

test('callGemini rejects malformed JSON content', async () => {
  await assert.rejects(
    callGemini({
      apiKey: 'k',
      model: 'm',
      thinkingLevel: 'high',
      systemInstruction: 's',
      userText: 'u',
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({ candidates: [{ content: { parts: [{ text: '{not json' }] } }] }),
      }),
      sleep: noSleep,
    }),
    /not valid JSON/,
  );
});

test('runAiReview throws when GEMINI_API_KEY is missing', async () => {
  await assert.rejects(
    runAiReview({ files: [], hints: [], pr: {}, env: { AI_REVIEW_ENGINE: 'gemini' }, io: buildIo() }),
    /GEMINI_API_KEY is not configured/,
  );
});

test('runAiReview skips the API call when only generated files changed', async () => {
  const result = await runAiReview({
    files: [{ filename: 'a.g.dart', status: 'modified', patch: '+x' }],
    hints: [],
    pr: {},
    env: { AI_REVIEW_ENGINE: 'gemini', GEMINI_API_KEY: 'k' },
    io: buildIo(),
    fetchImpl: async () => {
      throw new Error('should not call Gemini');
    },
  });

  assert.deepEqual(result.findings, []);
  assert.match(result.llm.skipped, /No reviewable files/);
});

test('runAiReview returns normalized findings and llm metadata with default model', async () => {
  const review = {
    ...EMPTY_REVIEW,
    findings: [{ tier: 'important', path: 'a.dart', line: 1, symbol: 'f', message: 'm', why: 'w' }],
    tests_needed: ['cover the empty input case'],
  };

  const result = await runAiReview({
    files: [{ filename: 'a.dart', status: 'added', patch: '@@ -0,0 +1 @@\n+x' }],
    hints: [],
    pr: { title: 't', body: 'b' },
    env: { AI_REVIEW_ENGINE: 'gemini', GEMINI_API_KEY: 'k' },
    io: buildIo({ 'a.dart': 'x' }),
    fetchImpl: async () => buildGeminiResponse(review),
    sleep: noSleep,
  });

  assert.equal(result.findings[0].severity, 'blocking');
  assert.equal(result.llm.engine, 'gemini');
  assert.equal(result.llm.model, 'gemini-flash-latest');
  assert.equal(result.llm.model_version, 'gemini-3.8-flash');
  assert.equal(result.llm.thinking_level, 'high');
  assert.deepEqual(result.llm.tests_needed, ['cover the empty input case']);
});

function buildClaudeOutput(overrides = {}) {
  return JSON.stringify({
    type: 'result',
    subtype: 'success',
    is_error: false,
    result: JSON.stringify(EMPTY_REVIEW),
    structured_output: EMPTY_REVIEW,
    modelUsage: { 'claude-sonnet-5-5': {} },
    total_cost_usd: 0.12,
    ...overrides,
  });
}

test('toGeminiSchema uppercases JSON Schema types recursively', () => {
  const schema = toGeminiSchema({
    type: 'object',
    properties: { list: { type: 'array', items: { type: 'string', enum: ['a'] } }, count: { type: 'integer' } },
    required: ['list'],
  });

  assert.deepEqual(schema, {
    type: 'OBJECT',
    properties: { list: { type: 'ARRAY', items: { type: 'STRING', enum: ['a'] } }, count: { type: 'INTEGER' } },
    required: ['list'],
  });
});

test('callClaudeCode runs headless with tools disabled and returns structured output', async () => {
  let invocation;
  const result = await callClaudeCode({
    model: 'sonnet',
    effort: 'high',
    systemInstruction: 'system',
    userText: 'user',
    runCommand: async (args, input) => {
      invocation = { args, input };
      return { exitCode: 0, stdout: buildClaudeOutput(), stderr: '' };
    },
  });

  const flag = (name) => invocation.args[invocation.args.indexOf(name) + 1];
  assert.equal(invocation.input, 'user');
  assert.ok(invocation.args.includes('-p'));
  assert.equal(flag('--tools'), '');
  assert.equal(flag('--output-format'), 'json');
  assert.equal(flag('--system-prompt'), 'system');
  assert.equal(flag('--model'), 'sonnet');
  assert.equal(flag('--effort'), 'high');
  assert.deepEqual(JSON.parse(flag('--json-schema')), REVIEW_SCHEMA);
  assert.ok(invocation.args.includes('--strict-mcp-config'));
  assert.deepEqual(result, { review: EMPTY_REVIEW, modelVersion: 'claude-sonnet-5-5', costUsd: 0.12 });
});

test('callClaudeCode omits --model and --effort when not configured', async () => {
  let args;
  await callClaudeCode({
    model: '',
    effort: '',
    systemInstruction: 's',
    userText: 'u',
    runCommand: async (receivedArgs) => {
      args = receivedArgs;
      return { exitCode: 0, stdout: buildClaudeOutput(), stderr: '' };
    },
  });

  assert.equal(args.includes('--model'), false);
  assert.equal(args.includes('--effort'), false);
});

test('callClaudeCode fails on error results', async () => {
  await assert.rejects(
    callClaudeCode({
      model: '',
      systemInstruction: 's',
      userText: 'u',
      runCommand: async () => ({
        exitCode: 1,
        stdout: buildClaudeOutput({ is_error: true, subtype: 'error_during_execution', structured_output: undefined, result: 'usage limit reached' }),
        stderr: '',
      }),
    }),
    /Claude Code review failed \(error_during_execution\): usage limit reached/,
  );
});

test('callClaudeCode fails on non-JSON output', async () => {
  await assert.rejects(
    callClaudeCode({
      model: '',
      systemInstruction: 's',
      userText: 'u',
      runCommand: async () => ({ exitCode: 127, stdout: '', stderr: 'claude: command not found' }),
    }),
    /Claude Code exited with code 127: claude: command not found/,
  );
});

test('runAiReview defaults to the claude engine and requires a Claude credential', async () => {
  await assert.rejects(
    runAiReview({ files: [], hints: [], pr: {}, env: {}, io: buildIo() }),
    /CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY is not configured/,
  );
});

test('runAiReview rejects unknown engines', async () => {
  await assert.rejects(
    runAiReview({ files: [], hints: [], pr: {}, env: { AI_REVIEW_ENGINE: 'gpt' }, io: buildIo() }),
    /Unknown AI_REVIEW_ENGINE "gpt"/,
  );
});

test('runAiReview sends the same review payload through the claude engine', async () => {
  const review = {
    ...EMPTY_REVIEW,
    findings: [{ tier: 'critical', path: 'a.dart', line: 1, symbol: 'f', message: 'm', why: 'w' }],
  };
  let input;

  const result = await runAiReview({
    files: [{ filename: 'a.dart', status: 'added', patch: '@@ -0,0 +1 @@\n+x' }],
    hints: [],
    pr: { title: 'feat: a', body: '' },
    env: { CLAUDE_CODE_OAUTH_TOKEN: 'token', CLAUDE_MODEL: 'opus' },
    io: buildIo({ 'a.dart': 'x' }),
    runCommand: async (args, stdin) => {
      input = stdin;
      return { exitCode: 0, stdout: buildClaudeOutput({ structured_output: review, modelUsage: { 'claude-opus-5-5': {} } }), stderr: '' };
    },
  });

  assert.match(input, /<changed_file path="a.dart" status="added">/);
  assert.equal(result.findings[0].rule, 'llm_critical');
  assert.equal(result.llm.engine, 'claude');
  assert.equal(result.llm.model, 'opus');
  assert.equal(result.llm.effort, 'medium');
  assert.equal(result.llm.model_version, 'claude-opus-5-5');
  assert.equal(result.llm.cost_usd, 0.12);
  assert.equal(typeof result.llm.duration_seconds, 'number');
});

test('runAiReview runs claude with opus at medium effort by default and honors overrides', async () => {
  const flagsFor = async (env) => {
    let args;
    await runAiReview({
      files: [{ filename: 'a.dart', status: 'added', patch: '@@ -0,0 +1 @@\n+x' }],
      hints: [],
      pr: {},
      env: { CLAUDE_CODE_OAUTH_TOKEN: 'token', ...env },
      io: buildIo({ 'a.dart': 'x' }),
      runCommand: async (receivedArgs) => {
        args = receivedArgs;
        return { exitCode: 0, stdout: buildClaudeOutput(), stderr: '' };
      },
    });
    return { model: args[args.indexOf('--model') + 1], effort: args[args.indexOf('--effort') + 1] };
  };

  assert.deepEqual(await flagsFor({}), { model: 'opus', effort: 'medium' });
  assert.deepEqual(await flagsFor({ CLAUDE_MODEL: 'sonnet', CLAUDE_EFFORT: 'high' }), { model: 'sonnet', effort: 'high' });
});

test('buildReviewContext reads changed files through readChangedFile and guidance through readRepoFile', async () => {
  const io = {
    readRepoFile: async (path) => (path === 'AGENTS.md' ? 'trusted agents from base' : null),
    readChangedFile: async (file) => (file.filename === 'a.dart' ? 'head version' : null),
    listInstructionPaths: async () => [],
  };

  const context = await buildReviewContext(
    [
      { filename: 'a.dart', status: 'modified', patch: '@@ -1 +1 @@\n+head version' },
      { filename: 'missing.dart', status: 'modified', patch: '@@ -1 +1 @@\n+x' },
    ],
    io,
  );

  assert.equal(context.guidance[0].content, 'trusted agents from base');
  assert.match(context.files[0].content, /head version/);
  assert.equal(context.files[1].content, null);
  assert.equal(context.files[1].truncated, true);
  assert.deepEqual(context.truncatedFiles, ['missing.dart']);
});

test('parseRightSideLines ignores the trailing empty line of a patch', () => {
  assert.deepEqual([...parseRightSideLines('@@ -1,1 +1,2 @@\n line1\n+line2\n')], [1, 2]);
});

test('normalizeFindings keeps blocking findings on unknown paths as summary-only and drops non-blocking ones', () => {
  const findings = normalizeFindings(
    {
      findings: [
        { tier: 'critical', path: './a.dart', line: 1, symbol: '', message: 'bug', why: 'w' },
        { tier: 'suggestion', path: './a.dart', line: 1, symbol: '', message: 'nit', why: 'w' },
      ],
    },
    [{ filename: 'a.dart', patch: '@@ -0,0 +1 @@\n+x' }],
  );

  assert.deepEqual(
    findings.map(({ rule, severity, path, inline }) => ({ rule, severity, path, inline })),
    [{ rule: 'llm_critical', severity: 'blocking', path: './a.dart', inline: false }],
  );
});

test('REVIEW_SCHEMA requires design notes with kind, location, problem, direction, and worth_doing_now', () => {
  const designNotes = REVIEW_SCHEMA.properties.design_notes;
  assert.ok(REVIEW_SCHEMA.required.includes('design_notes'));
  assert.deepEqual(designNotes.items.properties.kind.enum, ['duplication', 'design', 'refactor']);
  assert.deepEqual(designNotes.items.required, ['kind', 'location', 'problem', 'direction', 'worth_doing_now']);
});

test('runAiReview passes design notes through to llm metadata', async () => {
  const note = { kind: 'duplication', location: 'a.dart:fetch', problem: 'p', direction: 'd', worth_doing_now: false };
  const result = await runAiReview({
    files: [{ filename: 'a.dart', status: 'added', patch: '@@ -0,0 +1 @@\n+x' }],
    hints: [],
    pr: {},
    env: { CLAUDE_CODE_OAUTH_TOKEN: 'token' },
    io: buildIo({ 'a.dart': 'x' }),
    runCommand: async () => ({
      exitCode: 0,
      stdout: buildClaudeOutput({ structured_output: { ...EMPTY_REVIEW, design_notes: [note] } }),
      stderr: '',
    }),
  });

  assert.deepEqual(result.llm.design_notes, [note]);
});

test('buildClaudeChildEnv strips repository and other-engine credentials but keeps Claude auth', () => {
  const env = buildClaudeChildEnv({
    PATH: '/usr/bin',
    CLAUDE_CODE_OAUTH_TOKEN: 'claude',
    GH_TOKEN: 'gh',
    GITHUB_TOKEN: 'github',
    GEMINI_API_KEY: 'gemini',
  });

  assert.deepEqual(env, { PATH: '/usr/bin', CLAUDE_CODE_OAUTH_TOKEN: 'claude' });
});
