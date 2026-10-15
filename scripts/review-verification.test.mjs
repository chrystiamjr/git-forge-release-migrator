import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runAiReview } from './ai-review.mjs';
import { publishReviewResult } from './publish-pr-review.mjs';
import { ReviewStopped } from './review-lifecycle.mjs';
import { isolatedReview, subscriptionEnv, readOnlyArgs, boundedProcess } from './review-runner.mjs';
import { validateDecisions, verificationCandidates, verifyReview, verificationMode } from './review-verification.mjs';
import { parseEffortlessProof, buildRiskSummary, effortlessConfiguration, validateEffortlessPlugin } from './review-effortless.mjs';
import { benchmarkPrompt, validateCorpus, scoreBenchmark, runBenchmarkCase } from './review-benchmark.mjs';

const finding = { tier: 'bug', path: 'a.dart', line: 1, symbol: 'run', message: 'bad', why: 'breaks', previous_finding_id: '' };
const review = { findings: [finding], prior_assessments: [], test_requirements: [], design_notes: [], dismissed_hints: [] };
const decision = { id: 'findings:0', decision: 'substantiated', reason: 'Caller uses this value',
  evidence: [{ path: 'a.dart', line: 1, quote: 'bad();' }] };
const goodRun = async () => ({ output: { decisions: [decision] } });

test('verification defaults off and refuses typo modes', async () => {
  assert.equal(verificationMode({}), 'off');
  assert.throws(() => verificationMode({ AI_REVIEW_VERIFICATION_MODE: 'on' }));
  assert.equal((await verifyReview({ review, mode: 'off', run: () => assert.fail() })).review, review);
});

test('verifier validates real quotes, complete coverage and unique known IDs', async () => {
  const candidates = verificationCandidates(review);
  await validateDecisions({ decisions: [decision] }, candidates, async () => 'bad();\n');
  for (const output of [{ decisions: [] }, { decisions: [decision, decision] },
    { decisions: [{ ...decision, id: 'invented' }] }, { decisions: [{ ...decision, evidence: [] }] },
    { decisions: [{ ...decision, evidence: [{ path: '../secret', line: 1, quote: 'secret' }] }] },
    { decisions: [{ ...decision, evidence: [{ path: 'a.dart', line: 0, quote: 'bad();' }] }] },
    { decisions: [{ ...decision, evidence: [{ path: 'a.dart', line: 1.5, quote: 'bad();' }] }] }]) {
    await assert.rejects(validateDecisions(output, candidates, async () => 'bad();\n'));
  }
});

test('source citations accept exact fragments on the cited line and reject altered or absent text', async () => {
  const candidates = verificationCandidates(review);
  await validateDecisions({ decisions: [decision] }, candidates, async () => '    bad();\n');
  const testName = { ...decision, evidence: [{ path: 'a.dart', line: 1, quote: 'retries 429 responses' }] };
  await validateDecisions({ decisions: [testName] }, candidates, async () => "    test('retries 429 responses', () {\n");
  const multiline = { ...decision, evidence: [{ path: 'a.dart', line: 1, quote: 'bad();\n  next();' }] };
  await validateDecisions({ decisions: [multiline] }, candidates, async () => '    bad();\n  next();\n');
  await assert.rejects(validateDecisions({ decisions: [multiline] }, candidates, async () => '    bad();\n    next();\n'));
  await assert.rejects(validateDecisions({ decisions: [decision] }, candidates, async () => '    good();\n'), /findings:0.*a.dart:1/);
});

test('wrong lines relocate only unique exact quotes in the same file and record the original line', async () => {
  for (const [source, reported, actual, quote] of [
    ['good();\n    bad();\n', 1, 2, 'bad();'],
    ['    bad();\n', 999, 1, 'bad();'],
    ['good();\n    bad();\n  next();\n', 3, 2, 'bad();\n  next();'],
  ]) {
    const output = { decisions: [{ ...decision, evidence: [{ path: 'a.dart', line: reported, quote }] }] };
    const original = structuredClone(output);
    const result = await validateDecisions(output, verificationCandidates(review), async (path) => {
      assert.equal(path, 'a.dart');
      return source;
    });
    assert.deepEqual(result.decisions[0].evidence, [{ path: 'a.dart', line: actual, quote }]);
    assert.deepEqual(result.citation_corrections, [{ id: 'findings:0', path: 'a.dart',
      reported_line: reported, corrected_line: actual }]);
    assert.deepEqual(output, original, 'Raw model evidence must remain unchanged');
  }
});

test('wrong lines reject duplicate and overlapping matches while valid repeated quotes stay unchanged', async () => {
  for (const [source, quote] of [['bad();\nbad();\n', 'bad();'], ['aaaa', 'aaa']]) {
    const output = { decisions: [{ ...decision, evidence: [{ path: 'a.dart', line: 3, quote }] }] };
    await assert.rejects(validateDecisions(output, verificationCandidates(review), async () => source), /findings:0.*a.dart:3/);
  }
  const output = { decisions: [{ ...decision, evidence: [{ path: 'a.dart', line: 2, quote: 'bad();' }] }] };
  const result = await validateDecisions(output, verificationCandidates(review), async () => 'bad();\nbad();\n');
  assert.deepEqual(result.decisions, output.decisions);
  assert.deepEqual(result.citation_corrections, []);
});

test('corrected citations survive runner normalization without changing the raw response', async () => {
  const root = await mkdtemp(join(tmpdir(), 'gfrm-corrected-evidence-'));
  try {
    await mkdir(join(root, 'work/repo'), { recursive: true });
    await writeFile(join(root, 'work/repo/a.dart'), 'good();\n    bad();\n');
    for (const keyed of [false, true]) {
      const { id, ...value } = structuredClone(decision);
      const output = { decisions: keyed ? { [id]: value } : [{ id, ...value }] };
      const original = structuredClone(output);
      const result = await verifyReview({ review, mode: 'enforce', run: async ({ validate }) => {
        await validate(output, { root });
        return { output };
      } });
      assert.equal(result.verification.status, 'complete');
      assert.equal(result.verification.decisions[0].evidence[0].line, 2);
      assert.deepEqual(result.verification.citation_corrections, [{ id, path: 'a.dart', reported_line: 1, corrected_line: 2 }]);
      assert.deepEqual(result.review.findings, [finding]);
      assert.deepEqual(output, original);
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('a correction followed by invalid evidence retains raw diagnostics without accepting partial findings', async () => {
  const root = await mkdtemp(join(tmpdir(), 'gfrm-invalid-evidence-'));
  try {
    await mkdir(join(root, 'work/repo'), { recursive: true });
    await writeFile(join(root, 'work/repo/a.dart'), 'good();\n    bad();\n');
    const mixed = { ...decision, evidence: [...decision.evidence, { path: 'a.dart', line: 2, quote: 'different();' }] };
    const result = await verifyReview({ review, mode: 'enforce', run: async ({ validate }) => {
      await validate({ decisions: [mixed] }, { root });
      assert.fail('Invalid evidence must stop verification');
    } });
    assert.equal(result.verification.status, 'incomplete');
    assert.deepEqual(result.verification.received_decisions, [mixed]);
    assert.deepEqual(result.verification.decisions, []);
    assert.deepEqual(result.review.findings, []);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('benchmark rerun preserves existing report and stops before network or model work', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'gfrm-existing-report-'));
  try {
    const path = join(directory, 'case-01-current.json');
    await writeFile(path, 'original evidence');
    await assert.rejects(runBenchmarkCase({ id: 'case-01' }, 'current', directory, {}), /Report already exists/);
    assert.equal(await readFile(path, 'utf8'), 'original evidence');
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('shadow keeps baseline while enforce suppresses rejected and inconclusive claims', async () => {
  for (const verdict of ['rejected', 'inconclusive']) {
    const run = async () => ({ output: { decisions: [{ ...decision, decision: verdict, evidence: [] }] } });
    assert.equal((await verifyReview({ review, mode: 'shadow', run })).review, review);
    const enforced = await verifyReview({ review, mode: 'enforce', run });
    assert.deepEqual(enforced.review.findings, []);
    assert.equal(enforced.verification.candidates.length, 1);
  }
  assert.equal((await verifyReview({ review, mode: 'enforce', run: goodRun })).review.findings.length, 1);
});

test('quota, invalid schema and timeout fail without new findings, but closure propagates', async () => {
  for (const reason of ['quota', 'Verification deadline exceeded', 'Invalid schema']) {
    const result = await verifyReview({ review, mode: 'enforce', run: async () => { throw new Error(reason); } });
    assert.equal(result.verification.status, 'incomplete');
    assert.deepEqual(result.review.findings, []);
  }
  await assert.rejects(verifyReview({ review, mode: 'enforce', run: async () => { throw new ReviewStopped('merged'); } }), ReviewStopped);
});

async function integrated(mode, runner, detected = review, history = []) {
  return runAiReview({ files: [{ filename: 'a.dart', status: 'added', patch: '@@ -0,0 +1 @@\n+bad();' }], hints: [],
    pr: { repository: 'owner/repo', head_sha: 'a'.repeat(40) }, priorComments: history,
    env: { AI_REVIEW_VERIFICATION_MODE: mode, CLAUDE_CODE_OAUTH_TOKEN: 'test-only', CLAUDE_MODEL: 'sonnet' },
    io: { listInstructionPaths: async () => [], readRepoFile: async () => '', readChangedFile: async () => 'bad();' },
    runCommand: async () => ({ exitCode: 0, stdout: JSON.stringify({ subtype: 'success', structured_output: detected }), stderr: '' }),
    verificationRunner: runner });
}

test('integration: failure retains old blockers and suppresses unverified clearing and new tests', async () => {
  const prior = { finding_id: 'old', tier: 'bug', path: 'a.dart', state: 'applicable' };
  const result = await integrated('enforce', async () => { throw new Error('quota'); }, {
    ...review, prior_assessments: [{ finding_id: 'old', state: 'fixed', reason: 'detector says fixed' }],
    test_requirements: [{ id: 'new', implementation_verified: true }],
  }, [prior, { ...prior, finding_id: 'resolved', state: 'answered' }]);
  assert.equal(result.findings.length, 1);
  assert.equal(result.findings[0].finding_id, 'old');
  assert.equal(result.findings[0].severity, 'blocking');
  assert.deepEqual(result.llm.prior_assessments, []);
  assert.deepEqual(result.llm.test_requirements, []);
  assert.equal(result.llm.error, undefined);
});

test('integration: shadow keeps baseline publication; successful verification can clear old blockers', async () => {
  const rejected = async () => ({ output: { decisions: [{ ...decision, decision: 'rejected' }] } });
  assert.equal((await integrated('shadow', rejected)).findings.length, 1);
  const clear = { findings: [], prior_assessments: [{ finding_id: 'old', state: 'fixed', reason: 'source proves fix' }] };
  const result = await integrated('enforce', async () => ({ output: { decisions: [{ ...decision, id: 'prior_assessments:0' }] } }), clear,
    [{ finding_id: 'old', tier: 'bug', path: 'a.dart' }]);
  assert.deepEqual(result.findings, []);
});

test('bot-closed history behaves consistently across verification modes', async () => {
  const empty = { ...review, findings: [] };
  for (const mode of ['off', 'shadow', 'enforce']) {
    for (const state of ['fixed', 'answered']) {
      const prior = { finding_id: 'old', tier: 'bug', path: 'a.dart', state };
      const result = await integrated(mode, goodRun, empty, [prior]);
      assert.deepEqual(result.findings, [], `${mode}/${state}`);
    }
    const pending = await integrated(mode, goodRun, empty, [{ finding_id: 'old', tier: 'bug', state: 'applicable' }]);
    assert.equal(pending.findings[0].severity, 'blocking', mode);
  }
});

test('incomplete shadow verification preserves baseline approval with accurate wording', async () => {
  const submitted = [];
  await publishReviewResult({ verdict: 'approve', findings: [], marker: '<!-- auto-pr-review -->',
    llm: { verification: { mode: 'shadow', status: 'incomplete' } } },
  async (event, body) => submitted.push({ event, body }));
  assert.equal(submitted[0].event, 'APPROVE');
  assert.match(submitted[0].body, /baseline verdict is unchanged/);
  assert.doesNotMatch(submitted[0].body, /not a clean AI approval/);
});

test('incomplete verification publishes a counted comment, never a formal approval', async () => {
  const result = await integrated('enforce', async () => { throw new Error('timeout'); });
  const submitted = [];
  await publishReviewResult({ ...result, verdict: 'approve', marker: '<!-- auto-pr-review -->' },
    async (event, body) => submitted.push({ event, body }));
  assert.equal(submitted[0].event, 'COMMENT');
  assert.match(submitted[0].body, /verification is incomplete/);
  assert.match(submitted[0].body, /auto-pr-review:llm/);
});

test('subscription runner never inherits credentials, config injection or API billing', () => {
  const env = subscriptionEnv({ PATH: '/bin', CLAUDE_CODE_OAUTH_TOKEN: 'test-only', GH_TOKEN: 'secret',
    GH_PERSONAL_TOKEN: 'secret', ANTHROPIC_API_KEY: 'secret', NODE_OPTIONS: '--require attack',
    CLAUDE_CODE_ENABLE_FUNCTION_HOOKS: '1' }, '/isolated');
  assert.deepEqual(Object.keys(env).sort(), ['PATH', 'HOME', 'TMPDIR', 'CLAUDE_CONFIG_DIR', 'CLAUDE_CODE_OAUTH_TOKEN',
    'CLAUDE_CODE_DISABLE_AUTO_MEMORY', 'DISABLE_AUTOUPDATER'].sort());
  assert.throws(() => subscriptionEnv({ ANTHROPIC_API_KEY: 'secret' }, '/isolated'));
  const args = readOnlyArgs({ system: 'verify', schema: {} });
  assert.equal(args[args.indexOf('--tools') + 1], 'Read,Grep,Glob');
  assert.ok(args.includes('--safe-mode'));
  assert.ok(args.includes('--restricted'));
  assert.ok(!args.includes('--dangerously-skip-permissions'));
});

test('runner uses pinned CLI, validates before cleanup and confines cwd to data workdir', async () => {
  let root;
  const result = await isolatedReview({ env: { PATH: process.env.PATH, CLAUDE_CODE_OAUTH_TOKEN: 'test-only' },
    snapshot: async (options) => { root = options.root; await mkdir(join(root, 'work/repo'), { recursive: true }); },
    run: async (command, args, options) => {
      assert.equal(command, 'claude');
      if (args[0] === '--version') return { exitCode: 0, stdout: '2.1.296 (Claude Code)' };
      assert.equal(options.cwd, join(root, 'work'));
      return { exitCode: 0, stdout: JSON.stringify({ subtype: 'success', structured_output: { decisions: [] } }) };
    }, validate: async () => assert.ok(root), input: '', schema: {}, system: '' });
  assert.deepEqual(result.output.decisions, []);
  await assert.rejects(readFile(join(root, 'missing')), { code: 'ENOENT' });
});

test('deadline kills the process and unsupported CLI never downloads source', async () => {
  const env = { PATH: process.env.PATH, CLAUDE_CODE_OAUTH_TOKEN: 'test-only' };
  await assert.rejects(isolatedReview({ env, timeoutMs: 30, run: async (_, args, options) =>
    args[0] === '--version' ? { exitCode: 0, stdout: '2.1.296 (Claude Code)' }
      : boundedProcess(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], options),
  snapshot: async ({ root }) => mkdir(join(root, 'work'), { recursive: true }), schema: {}, system: '' }), /deadline/);
  await assert.rejects(isolatedReview({ env, run: async () => ({ exitCode: 0, stdout: '2.1.282 (Claude Code)' }),
    snapshot: async () => assert.fail('Unsupported CLI must stop') }), /requires Claude Code/);
});

test('Effortless proof distinguishes recommendations from applied request settings', () => {
  const parsed = parseEffortlessProof('judged by haiku in 900 ms: opus/high\nrequest 0 (claude-sonnet): effort medium -> high\n');
  assert.equal(parsed.suggested_settings[0].model, 'opus');
  assert.equal(parsed.applied_settings[0].model, 'claude-sonnet');
  assert.equal(parsed.usage_complete, false);
  assert.throws(() => parseEffortlessProof('judged by haiku in 900 ms: opus/high'), /evidence/);
  assert.throws(() => parseEffortlessProof('judged by jev in 90 ms: opus/high\nrequest 0 (opus): effort medium -> high'), /Non-subscription/);
});

test('invalid plugin contract stops the trial before its hooks can run', async () => {
  await assert.rejects(validateEffortlessPlugin('/plugin', {}, async () => ({ exitCode: 1 })), /static validation/);
});

test('live closure guards prevent snapshot/model work; stalled guards respect the deadline', async () => {
  await assert.rejects(isolatedReview({ env: { CLAUDE_CODE_OAUTH_TOKEN: 'test-only' },
    assertCurrent: async () => { throw new ReviewStopped('merged'); }, run: async () => assert.fail() }), ReviewStopped);
  await assert.rejects(isolatedReview({ env: { CLAUDE_CODE_OAUTH_TOKEN: 'test-only' }, timeoutMs: 20,
    assertCurrent: () => new Promise(() => {}), run: async () => assert.fail() }), /deadline/);
});

test('Effortless configuration pins source, uses Haiku and toggles model routing separately', async () => {
  const root = await mkdtemp(join(tmpdir(), 'gfrm-plugin-test-'));
  try {
    await mkdir(join(root, '.claude-plugin'));
    await writeFile(join(root, '.claude-plugin/plugin.json'), JSON.stringify({ name: 'effortless', version: '1.71.0' }));
    for (const arm of ['effortless-effort', 'effortless-model']) {
      const args = readOnlyArgs({ schema: {}, system: '' });
      const env = {};
      await effortlessConfiguration(arm, async ({ head }) => { assert.equal(head.length, 40); return root; }, async () => {})({ root, args, env });
      const settings = JSON.parse(args[args.indexOf('--settings') + 1]).pluginConfigs['effortless@inline'].options;
      assert.equal(settings.judge, 'haiku');
      assert.equal(settings.modelAuto, arm === 'effortless-model' ? 'on' : 'off');
      assert.ok(args.includes('--restricted'));
      assert.ok(!args.includes('--safe-mode'));
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('benchmark excludes labels, replies and hindsight from prompts', () => {
  const prompt = benchmarkPrompt({ guidance: [], files: [], omittedFiles: [] }, [],
    { pr: 73, rationale: 'HINDSIGHT', claim: 'SECRET_LABEL', adjudication_only_replies: ['FUTURE_REPLY'] });
  assert.doesNotMatch(prompt, /HINDSIGHT|SECRET_LABEL|FUTURE_REPLY/);
  assert.ok(buildRiskSummary(Array.from({ length: 1000 }, () => ({ filename: 'providers/long/path.dart' }))).length < 2000);
});

test('benchmark gates require labels, complete trials and preserve baseline real bugs', () => {
  const cases = Array.from({ length: 12 }, (_, index) => ({ id: `c${index}`, head_sha: 'a'.repeat(40), base_sha: 'b'.repeat(40),
    confirmed_label: index < 6 ? 'false_positive' : index < 10 ? 'real_bug' : 'clean' }));
  const corpus = { schema_version: 1, cases, confirmed_by: 'maintainer' };
  assert.throws(() => validateCorpus({ ...corpus, confirmed_by: null }));
  const reports = cases.map((item, index) => ({ case_id: item.id, head_sha: item.head_sha, base_sha: item.base_sha,
    arm: 'current', verification: { status: 'complete' }, adjudication: { confirmed_by: 'maintainer',
      baseline_detected: index < 10, candidate_detected: index >= 3 && index < 10 } }));
  assert.equal(scoreBenchmark(corpus, reports).status, 'passed');
  reports[6].adjudication.candidate_detected = false;
  assert.equal(scoreBenchmark(corpus, reports).status, 'failed');
  assert.equal(scoreBenchmark(corpus, reports.slice(1)).status, 'pending');
  reports[0].verification.status = 'incomplete';
  reports[0].verification.reason = 'Verifier must assess every candidate';
  const incomplete = scoreBenchmark(corpus, reports.slice(0, 1));
  assert.equal(incomplete.status, 'pending');
  assert.match(incomplete.pending_details[0].reasons.join(' '), /Verifier must assess every candidate/);
  assert.match(incomplete.pending_details[1].reasons.join(' '), /Report missing/);
  assert.equal(incomplete.scored_cases, 0);
});

test('verifier wire schema requires each finding and test-requirement decision', async () => {
  const detected = { ...review, test_requirements: [{ id: 'required-test' }] };
  const result = await verifyReview({ review: detected, mode: 'enforce', run: async ({ schema }) => {
    assert.equal(schema.properties.decisions.type, 'object');
    assert.deepEqual(schema.properties.decisions.required, ['findings:0', 'test_requirements:0']);
    return { output: { decisions: {
      'findings:0': { decision: 'rejected', reason: 'Unchanged adapter handles it', evidence: [] },
      'test_requirements:0': { decision: 'inconclusive', reason: 'Not inspected', evidence: [] },
    } } };
  } });
  assert.equal(result.verification.status, 'complete');
  assert.deepEqual(result.review.findings, []);
});

test('snapshot extractor excludes links and configuration and rejects traversal', async () => {
  const root = await mkdtemp(join(tmpdir(), 'gfrm-archive-test-'));
  const extractor = new URL('./review-snapshot.py', import.meta.url).pathname;
  const python = `import io,tarfile,sys\np=sys.argv[1]\nwith tarfile.open(p,'w') as t:\n for n in ['top/a.dart','top/CLAUDE.md','top/.claude/settings.json']:\n  i=tarfile.TarInfo(n);i.size=4;t.addfile(i,io.BytesIO(b'data'))\n i=tarfile.TarInfo('top/link');i.type=tarfile.SYMTYPE;i.linkname='/etc/passwd';t.addfile(i)\n`;
  try {
    await boundedProcess('python3', ['-c', python, join(root, 'safe.tar')]);
    const result = await boundedProcess('python3', [extractor, join(root, 'safe.tar'), join(root, 'repo')]);
    assert.equal(result.exitCode, 0);
    assert.equal(await readFile(join(root, 'repo/a.dart'), 'utf8'), 'data');
    for (const path of ['CLAUDE.md', '.claude/settings.json', 'link']) await assert.rejects(readFile(join(root, 'repo', path)));
    await boundedProcess('python3', ['-c', python.replace('top/a.dart', '../escape'), join(root, 'bad.tar')]);
    assert.notEqual((await boundedProcess('python3', [extractor, join(root, 'bad.tar'), join(root, 'bad')])).exitCode, 0);
  } finally { await rm(root, { recursive: true, force: true }); }
});
