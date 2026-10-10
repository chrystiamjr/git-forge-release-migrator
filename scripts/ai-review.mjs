#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_ENGINE = 'claude';

const GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models';
const DEFAULT_GEMINI_MODEL = 'gemini-flash-latest';
const DEFAULT_GEMINI_THINKING_LEVEL = 'high';
const REQUEST_TIMEOUT_IN_MILLISECONDS = 180_000;
// Gemini returns 503 "high demand" spikes; back off 2s, 4s, 8s before failing closed.
const INITIAL_RETRY_DELAY_IN_MILLISECONDS = 2_000;
const MAX_ATTEMPTS = 4;
const RETRYABLE_STATUS_CODES = new Set([429, 500, 502, 503, 504]);

const DEFAULT_CLAUDE_EFFORT = 'medium';
const CLAUDE_TIMEOUT_IN_MILLISECONDS = 600_000;
const CLAUDE_OUTPUT_EXCERPT_LENGTH = 500;

// Unless CLAUDE_MODEL pins a model, a cheap Haiku triage call picks the review tier for each PR.
const TRIAGE_MODEL = 'haiku';
const TRIAGE_EFFORT = 'low';
const ROUTE_TIERS = {
  light: { model: 'haiku', effort: 'low' },
  standard: { model: 'sonnet', effort: 'medium' },
  deep: { model: 'opus', effort: 'medium' },
};
const FALLBACK_TIER = 'standard';
// ~50K tokens: keeps the triage prompt inside Haiku's lowest price tier (prompts up to 100K tokens).
const TRIAGE_CHAR_BUDGET = 200_000;
// Docs-only PRs skip the triage call and go straight to the light tier.
const DOCS_ONLY_PATTERNS = [/^website\/.*\.mdx?$/, /(^|\/)README\.md$/];

// ~150K tokens: keeps prompts under the >200K-token price tier.
const CONTEXT_CHAR_BUDGET = 600_000;
const MAX_INLINE_FINDINGS = 20;
// One GitHub Contents API call per file; stay well under GitHub's secondary rate limit on concurrent requests.
const MAX_CONCURRENT_FILE_READS = 8;

const TIERS = ['critical', 'bug', 'important', 'suggestion', 'question'];
// Only these tiers block a merge; every other finding is posted as a plain comment.
export const BLOCKING_TIERS = new Set(['critical', 'bug', 'important']);

const AGENTS_PATH = 'AGENTS.md';
const INSTRUCTIONS_DIR = '.github/instructions';
const PROMPT_PATH = fileURLToPath(new URL('./ai-review-prompt.md', import.meta.url));
const TRIAGE_PROMPT_PATH = fileURLToPath(new URL('./ai-review-triage-prompt.md', import.meta.url));

const SKIPPED_FILE_PATTERNS = [
  /\.g\.dart$/,
  /\.freezed\.dart$/,
  /(^|\/)(yarn|pubspec)\.lock$/,
  /(^|\/)package-lock\.json$/,
  /(^|\/)CHANGELOG\.md$/,
  /\.(png|jpe?g|gif|ico|icns|webp|pdf|zip|ttf|otf|woff2?)$/i,
];

export const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          tier: { type: 'string', enum: TIERS },
          path: { type: 'string' },
          line: { type: 'integer' },
          symbol: { type: 'string' },
          message: { type: 'string' },
          why: { type: 'string' },
        },
        required: ['tier', 'path', 'line', 'symbol', 'message', 'why'],
      },
    },
    design_notes: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          kind: { type: 'string', enum: ['duplication', 'design', 'refactor'] },
          location: { type: 'string' },
          problem: { type: 'string' },
          direction: { type: 'string' },
          worth_doing_now: { type: 'boolean' },
        },
        required: ['kind', 'location', 'problem', 'direction', 'worth_doing_now'],
      },
    },
    dismissed_hints: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          rule: { type: 'string' },
          path: { type: 'string' },
          reason: { type: 'string' },
        },
        required: ['rule', 'path', 'reason'],
      },
    },
    tests_needed: { type: 'array', items: { type: 'string' } },
    verdict_reasoning: { type: 'string' },
  },
  required: ['findings', 'design_notes', 'dismissed_hints', 'tests_needed', 'verdict_reasoning'],
};

export const TRIAGE_SCHEMA = {
  type: 'object',
  properties: {
    tier: { type: 'string', enum: Object.keys(ROUTE_TIERS) },
    reason: { type: 'string' },
  },
  required: ['tier', 'reason'],
};

// Gemini's responseSchema uses the OpenAPI subset with uppercase type names.
export function toGeminiSchema(schema) {
  if (Array.isArray(schema)) {
    return schema.map(toGeminiSchema);
  }

  if (schema === null || typeof schema !== 'object') {
    return schema;
  }

  return Object.fromEntries(
    Object.entries(schema).map(([key, value]) => [
      key,
      key === 'type' && typeof value === 'string' ? value.toUpperCase() : toGeminiSchema(value),
    ]),
  );
}

async function readRepoFileFromDisk(path) {
  try {
    return await readFile(path, 'utf8');
  } catch {
    return null;
  }
}

async function listInstructionPathsFromDisk() {
  try {
    const entries = await readdir(INSTRUCTIONS_DIR);
    return entries.filter((entry) => entry.endsWith('.instructions.md')).map((entry) => `${INSTRUCTIONS_DIR}/${entry}`);
  } catch {
    return [];
  }
}

// Guidance (AGENTS.md, instructions) comes from the trusted checkout. Changed files default to the working tree,
// which only matches the PR head locally; CI overrides readChangedFile to fetch at the head SHA.
export const DISK_IO = {
  readRepoFile: readRepoFileFromDisk,
  readChangedFile: (file) => readRepoFileFromDisk(file.filename),
  listInstructionPaths: listInstructionPathsFromDisk,
};

export function globToRegex(glob) {
  const pattern = glob
    .split(/(\*\*\/|\*\*|\*)/)
    .map((part) => {
      if (part === '**/') return '(?:.*/)?';
      if (part === '**') return '.*';
      if (part === '*') return '[^/]*';
      return part.replace(/[|\\{}()[\]^$+?.]/g, '\\$&');
    })
    .join('');
  return new RegExp(`^${pattern}$`);
}

export function parseApplyTo(instructionContent) {
  const frontmatter = instructionContent.match(/^---\n([\s\S]*?)\n---/);
  const applyTo = frontmatter?.[1].match(/^applyTo:\s*["']?([^"'\n]+)["']?\s*$/m);
  if (!applyTo) {
    return [];
  }

  return applyTo[1]
    .split(',')
    .map((glob) => glob.trim())
    .filter(Boolean);
}

function isReviewableFile(file) {
  return file.status !== 'removed' && !SKIPPED_FILE_PATTERNS.some((pattern) => pattern.test(file.filename));
}

function withLineNumbers(content) {
  return content
    .split('\n')
    .map((line, index) => `${String(index + 1).padStart(5)} | ${line}`)
    .join('\n');
}

export async function buildReviewContext(files, io = DISK_IO) {
  const reviewableFiles = files.filter(isReviewableFile);
  const changedPaths = reviewableFiles.map((file) => file.filename);

  const guidance = [];
  const agents = await io.readRepoFile(AGENTS_PATH);
  if (agents) {
    guidance.push({ path: AGENTS_PATH, content: agents });
  }

  for (const instructionPath of (await io.listInstructionPaths()).sort()) {
    const content = await io.readRepoFile(instructionPath);
    const matchers = content ? parseApplyTo(content).map(globToRegex) : [];
    if (matchers.some((matcher) => changedPaths.some((path) => matcher.test(path)))) {
      guidance.push({ path: instructionPath, content });
    }
  }

  const contents = new Array(reviewableFiles.length);
  let nextIndex = 0;
  const readNext = async () => {
    while (nextIndex < reviewableFiles.length) {
      const index = nextIndex;
      nextIndex += 1;
      contents[index] = await io.readChangedFile(reviewableFiles[index]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(MAX_CONCURRENT_FILE_READS, reviewableFiles.length) }, readNext));
  const candidates = reviewableFiles.map((file, index) => ({
    path: file.filename,
    status: file.status,
    patch: file.patch ?? '',
    content: contents[index] === null ? null : withLineNumbers(contents[index]),
    truncated: contents[index] === null,
  }));

  let remainingBudget = CONTEXT_CHAR_BUDGET - guidance.reduce((total, entry) => total + entry.content.length, 0);
  const includedFiles = [];
  const truncatedFiles = [];
  const omittedFiles = [];

  // Smallest files first, so one huge file cannot crowd out the rest of the PR.
  const bySize = [...candidates].sort(
    (left, right) =>
      left.patch.length + (left.content?.length ?? 0) - (right.patch.length + (right.content?.length ?? 0)),
  );

  for (const candidate of bySize) {
    const fullSize = candidate.patch.length + (candidate.content?.length ?? 0);
    if (fullSize <= remainingBudget) {
      includedFiles.push(candidate);
      if (candidate.truncated) {
        truncatedFiles.push(candidate.path);
      }
      remainingBudget -= fullSize;
      continue;
    }

    if (candidate.patch.length <= remainingBudget) {
      includedFiles.push({ ...candidate, content: null, truncated: true });
      truncatedFiles.push(candidate.path);
      remainingBudget -= candidate.patch.length;
      continue;
    }

    omittedFiles.push(candidate.path);
  }

  const originalOrder = new Map(changedPaths.map((path, index) => [path, index]));
  includedFiles.sort((left, right) => originalOrder.get(left.path) - originalOrder.get(right.path));

  return { guidance, files: includedFiles, truncatedFiles, omittedFiles };
}

function formatHint(hint) {
  const location = hint.line ? `${hint.path}:${hint.line}` : hint.path;
  return `- [${hint.rule}] ${location} — ${hint.message}`;
}

function formatPriorComment(comment) {
  const replies = comment.replies.map((reply) => `  reply from ${reply.author}: ${reply.body}`);
  return [`- ${comment.path}:${comment.line ?? 'outdated'} ${comment.body}`, ...replies].join('\n');
}

export function buildUserPrompt(context, hints, pr, priorComments = []) {
  const sections = [
    `<pr>\ntitle: ${pr.title ?? ''}\n\n${pr.body ?? ''}\n</pr>`,
    ...context.guidance.map((entry) => `<repo_guidance path="${entry.path}">\n${entry.content}\n</repo_guidance>`),
    `<heuristic_hints>\n${hints.length > 0 ? hints.map(formatHint).join('\n') : '(none)'}\n</heuristic_hints>`,
  ];

  if (priorComments.length > 0) {
    sections.push(`<prior_review_comments>\n${priorComments.map(formatPriorComment).join('\n')}\n</prior_review_comments>`);
  }

  if (context.omittedFiles.length > 0) {
    sections.push(`<omitted_files>\n${context.omittedFiles.join('\n')}\n</omitted_files>`);
  }

  for (const file of context.files) {
    const truncatedAttribute = file.truncated ? ' truncated="true"' : '';
    const parts = [`<changed_file path="${file.path}" status="${file.status}"${truncatedAttribute}>`];
    parts.push(`<patch>\n${file.patch}\n</patch>`);
    if (file.content !== null) {
      parts.push(`<content>\n${file.content}\n</content>`);
    }
    parts.push('</changed_file>');
    sections.push(parts.join('\n'));
  }

  return sections.join('\n\n');
}

function defaultSleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export async function callGemini({
  apiKey,
  model,
  thinkingLevel,
  systemInstruction,
  userText,
  fetchImpl = fetch,
  sleep = defaultSleep,
}) {
  const url = `${GEMINI_ENDPOINT}/${encodeURIComponent(model)}:generateContent`;
  const body = JSON.stringify({
    systemInstruction: { parts: [{ text: systemInstruction }] },
    contents: [{ role: 'user', parts: [{ text: userText }] }],
    generationConfig: {
      responseMimeType: 'application/json',
      responseSchema: toGeminiSchema(REVIEW_SCHEMA),
      thinkingConfig: { thinkingLevel },
    },
  });

  let response;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      response = await fetchImpl(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
        body,
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_IN_MILLISECONDS),
      });
    } catch (error) {
      // Timeouts and connection resets are as likely as a 503 under high demand: retry them too.
      if (attempt === MAX_ATTEMPTS) {
        throw error;
      }
      response = null;
    }

    if (response && (response.ok || !RETRYABLE_STATUS_CODES.has(response.status) || attempt === MAX_ATTEMPTS)) {
      break;
    }

    await sleep(INITIAL_RETRY_DELAY_IN_MILLISECONDS * 2 ** (attempt - 1));
  }

  if (!response.ok) {
    const errorBody = await response.text();
    const attempts = RETRYABLE_STATUS_CODES.has(response.status) ? ` after ${MAX_ATTEMPTS} attempts` : '';
    throw new Error(`Gemini API ${response.status} for model ${model}${attempts}: ${errorBody.slice(0, 500)}`);
  }

  const payload = await response.json();
  const candidate = payload.candidates?.[0];
  const text = (candidate?.content?.parts ?? [])
    .filter((part) => !part.thought && typeof part.text === 'string')
    .map((part) => part.text)
    .join('');

  if (!text) {
    throw new Error(`Gemini returned no review content (finishReason: ${candidate?.finishReason ?? 'unknown'}).`);
  }

  let review;
  try {
    review = JSON.parse(text);
  } catch {
    throw new Error('Gemini returned review content that is not valid JSON.');
  }

  return { review, modelVersion: payload.modelVersion ?? model, costUsd: null };
}

export function parseRightSideLines(patch = '') {
  const lines = new Set();
  let newLine = 0;

  for (const line of patch.split('\n')) {
    if (line.startsWith('@@')) {
      const match = line.match(/@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
      if (match) {
        newLine = Number(match[1]);
      }
      continue;
    }

    if (newLine === 0 || line === '' || line.startsWith('-') || line.startsWith('\\')) {
      continue;
    }

    lines.add(newLine);
    newLine += 1;
  }

  return lines;
}

export function normalizeFindings(review, files) {
  const filesByPath = new Map(files.map((file) => [file.filename, file]));
  const findings = [];
  let inlineCount = 0;

  // Blocking findings first, so lower tiers never take their inline slots.
  const orderedFindings = [...(review.findings ?? [])].sort(
    (left, right) => Number(BLOCKING_TIERS.has(right.tier)) - Number(BLOCKING_TIERS.has(left.tier)),
  );

  for (const finding of orderedFindings) {
    const file = filesByPath.get(finding.path);
    const isBlocking = BLOCKING_TIERS.has(finding.tier);
    // Never drop a blocking finding because of a path mismatch: keep it in the summary so the verdict still blocks.
    if (!file && !isBlocking) {
      continue;
    }

    const isCommentable = Boolean(file) && parseRightSideLines(file.patch).has(finding.line);
    const inline = isCommentable && inlineCount < MAX_INLINE_FINDINGS;
    if (inline) {
      inlineCount += 1;
    }

    findings.push({
      rule: `llm_${finding.tier}`,
      severity: isBlocking ? 'blocking' : 'note',
      tier: finding.tier,
      path: finding.path,
      line: finding.line,
      symbol: finding.symbol || '',
      message: finding.message,
      why: finding.why,
      inline,
    });
  }

  return findings;
}

// Keep repository and other-engine credentials out of the model's process.
export function buildClaudeChildEnv(env) {
  const { GH_TOKEN, GITHUB_TOKEN, GEMINI_API_KEY, ...childEnv } = env;
  return childEnv;
}

function runClaudeCli(args, input) {
  return new Promise((resolve, reject) => {
    mkdtemp(join(tmpdir(), 'ai-review-')).then((emptyDir) => {
      // Run from an empty dir so no repo .claude/ settings, hooks, or CLAUDE.md are loaded.
      const child = spawn('claude', args, {
        cwd: emptyDir,
        env: buildClaudeChildEnv(process.env),
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      const stdout = [];
      const stderr = [];
      const timeout = setTimeout(() => child.kill('SIGTERM'), CLAUDE_TIMEOUT_IN_MILLISECONDS);
      const cleanUp = () => {
        clearTimeout(timeout);
        rm(emptyDir, { recursive: true, force: true }).catch(() => {});
      };

      child.stdout.on('data', (chunk) => stdout.push(chunk));
      child.stderr.on('data', (chunk) => stderr.push(chunk));
      child.on('error', (error) => {
        cleanUp();
        reject(error);
      });
      child.on('close', (exitCode) => {
        cleanUp();
        resolve({
          exitCode,
          stdout: Buffer.concat(stdout).toString('utf8'),
          stderr: Buffer.concat(stderr).toString('utf8'),
        });
      });
      child.stdin.end(input);
    }, reject);
  });
}

export async function callClaudeCode({
  model,
  effort,
  systemInstruction,
  userText,
  schema = REVIEW_SCHEMA,
  runCommand = runClaudeCli,
}) {
  const args = [
    '-p',
    '--output-format',
    'json',
    '--tools',
    '',
    '--strict-mcp-config',
    '--no-session-persistence',
    '--system-prompt',
    systemInstruction,
    '--json-schema',
    JSON.stringify(schema),
  ];
  if (model) {
    args.push('--model', model);
  }
  if (effort) {
    args.push('--effort', effort);
  }

  const { exitCode, stdout, stderr } = await runCommand(args, userText);

  let payload;
  try {
    payload = JSON.parse(stdout);
  } catch {
    const output = (stderr || stdout).trim().slice(0, CLAUDE_OUTPUT_EXCERPT_LENGTH);
    throw new Error(`Claude Code exited with code ${exitCode}: ${output}`);
  }

  if (payload.is_error || payload.subtype !== 'success' || !payload.structured_output) {
    const detail = String(payload.result ?? '').slice(0, CLAUDE_OUTPUT_EXCERPT_LENGTH);
    throw new Error(`Claude Code review failed (${payload.subtype ?? 'unknown'}): ${detail}`);
  }

  return {
    review: payload.structured_output,
    modelVersion: Object.keys(payload.modelUsage ?? {}).join(', ') || model || 'default',
    // API-equivalent estimate; on a subscription token it is quota usage, not a charge.
    costUsd: typeof payload.total_cost_usd === 'number' ? payload.total_cost_usd : null,
  };
}

export function buildTriagePrompt(context, pr) {
  const sections = [`<pr>\ntitle: ${pr.title ?? ''}\n\n${pr.body ?? ''}\n</pr>`];
  let remainingBudget = TRIAGE_CHAR_BUDGET;

  for (const file of context.files) {
    const header = `<changed_file path="${file.path}" status="${file.status}">`;
    if (file.patch.length <= remainingBudget) {
      sections.push(`${header}\n${file.patch}\n</changed_file>`);
      remainingBudget -= file.patch.length;
    } else {
      sections.push(`${header}\n(patch omitted: size budget)\n</changed_file>`);
    }
  }

  if (context.omittedFiles.length > 0) {
    sections.push(`<omitted_files>\n${context.omittedFiles.join('\n')}\n</omitted_files>`);
  }

  return sections.join('\n\n');
}

function routeTo(tier, reason, triageCostUsd = null) {
  return { ...ROUTE_TIERS[tier], tier, route_reason: reason, triage_cost_usd: triageCostUsd };
}

// Triage only saves cost, so it fails soft to the standard tier; the review itself still fails closed.
export async function routeClaudeReview({ context, pr, runCommand = runClaudeCli }) {
  const paths = [...context.files.map((file) => file.path), ...context.omittedFiles];
  if (paths.every((path) => DOCS_ONLY_PATTERNS.some((pattern) => pattern.test(path)))) {
    return routeTo('light', 'Docs-only change.');
  }

  try {
    const { review: triage, costUsd } = await callClaudeCode({
      model: TRIAGE_MODEL,
      effort: TRIAGE_EFFORT,
      systemInstruction: await readFile(TRIAGE_PROMPT_PATH, 'utf8'),
      userText: buildTriagePrompt(context, pr),
      schema: TRIAGE_SCHEMA,
      runCommand,
    });

    if (!Object.hasOwn(ROUTE_TIERS, triage.tier)) {
      throw new Error(`unknown tier "${triage.tier}"`);
    }

    return routeTo(triage.tier, triage.reason, costUsd);
  } catch (error) {
    console.error(`[ai-review] Triage failed, using the ${FALLBACK_TIER} tier: ${error.message}`);
    return routeTo(FALLBACK_TIER, 'Triage unavailable.');
  }
}

// Every engine receives the same system prompt, user prompt, and schema, and returns { review, modelVersion }.
const ENGINES = {
  claude: {
    assertConfigured(env) {
      if (!env.CLAUDE_CODE_OAUTH_TOKEN && !env.ANTHROPIC_API_KEY) {
        throw new Error('CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY is not configured.');
      }
    },
    async settings({ env, context, pr, runCommand }) {
      if (env.CLAUDE_MODEL) {
        return { model: env.CLAUDE_MODEL, effort: env.CLAUDE_EFFORT || DEFAULT_CLAUDE_EFFORT };
      }

      return routeClaudeReview({ context, pr, runCommand });
    },
    review({ settings, systemInstruction, userText, runCommand }) {
      return callClaudeCode({ model: settings.model, effort: settings.effort, systemInstruction, userText, runCommand });
    },
  },
  gemini: {
    assertConfigured(env) {
      if (!env.GEMINI_API_KEY) {
        throw new Error('GEMINI_API_KEY is not configured.');
      }
    },
    async settings({ env }) {
      return {
        model: env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL,
        thinking_level: env.GEMINI_THINKING_LEVEL || DEFAULT_GEMINI_THINKING_LEVEL,
      };
    },
    review({ env, settings, systemInstruction, userText, fetchImpl, sleep }) {
      return callGemini({
        apiKey: env.GEMINI_API_KEY,
        model: settings.model,
        thinkingLevel: settings.thinking_level,
        systemInstruction,
        userText,
        fetchImpl,
        sleep,
      });
    },
  },
};

function sumCosts(...costs) {
  const known = costs.filter((cost) => typeof cost === 'number');
  return known.length > 0 ? known.reduce((total, cost) => total + cost, 0) : null;
}

export async function runAiReview({
  files,
  hints,
  pr,
  priorComments = [],
  env = process.env,
  io = DISK_IO,
  fetchImpl = fetch,
  sleep = defaultSleep,
  runCommand = runClaudeCli,
}) {
  const engineName = env.AI_REVIEW_ENGINE || DEFAULT_ENGINE;
  const engine = ENGINES[engineName];
  if (!engine) {
    throw new Error(`Unknown AI_REVIEW_ENGINE "${engineName}". Use one of: ${Object.keys(ENGINES).join(', ')}.`);
  }

  engine.assertConfigured(env);

  const context = await buildReviewContext(files, io);
  if (context.files.length === 0 && context.omittedFiles.length === 0) {
    return {
      findings: [],
      llm: {
        engine: engineName,
        skipped: 'No reviewable files (only generated, lock, binary, or removed files changed).',
      },
    };
  }

  const startedAt = Date.now();
  const settings = await engine.settings({ env, context, pr, runCommand });
  const systemInstruction = await readFile(PROMPT_PATH, 'utf8');
  const { review, modelVersion, costUsd } = await engine.review({
    env,
    settings,
    systemInstruction,
    userText: buildUserPrompt(context, hints, pr, priorComments),
    fetchImpl,
    sleep,
    runCommand,
  });

  const findings = normalizeFindings(review, files);
  return {
    findings,
    llm: {
      engine: engineName,
      ...settings,
      model_version: modelVersion,
      duration_seconds: (Date.now() - startedAt) / 1000,
      cost_usd: sumCosts(costUsd, settings.triage_cost_usd),
      // Whether the AI's own findings block, as opposed to deterministic rules; drives the round's blocking marker.
      blocking: findings.some((finding) => finding.severity === 'blocking'),
      tests_needed: review.tests_needed ?? [],
      design_notes: review.design_notes ?? [],
      verdict_reasoning: review.verdict_reasoning ?? '',
      dismissed_hints: review.dismissed_hints ?? [],
      truncated_files: context.truncatedFiles,
      omitted_files: context.omittedFiles,
    },
  };
}
