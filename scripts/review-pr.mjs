#!/usr/bin/env node

import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const AUTO_REVIEW_MARKER = '<!-- auto-pr-review -->';
const REVIEW_RESULT_PATH = process.env.REVIEW_RESULT_PATH || 'review-result.json';
const GH_TOKEN = process.env.GH_TOKEN;
const REPOSITORY = process.env.GITHUB_REPOSITORY;
const PR_NUMBER = Number(process.env.PR_NUMBER);
const RUN_ID = process.env.GITHUB_RUN_ID || '';

const SECRET_PATTERNS = [
  { rule: 'secret_github_pat', regex: /\bgithub_pat_[A-Za-z0-9_]{20,}\b/ },
  { rule: 'secret_github_token', regex: /\bgh[pousr]_[A-Za-z0-9]{20,}\b/ },
  { rule: 'secret_gitlab_token', regex: /\bglpat-[A-Za-z0-9_-]{20,}\b/ },
  { rule: 'secret_slack_token', regex: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/ },
  { rule: 'secret_google_api_key', regex: /\bAIza[0-9A-Za-z_-]{35}\b/ },
  { rule: 'secret_aws_access_key', regex: /\bAKIA[0-9A-Z]{16}\b/ },
  { rule: 'secret_private_key', regex: /-----BEGIN [A-Z ]*PRIVATE KEY-----/ },
];

const SUMMARY_SCHEMA_VERSION = 2;
const STRICT_SEMVER_PATTERN_EQUIVALENTS = new Set([
  '^v(\\d+)\\.(\\d+)\\.(\\d+)$',
  '^v([0-9]+)\\.([0-9]+)\\.([0-9]+)$',
]);

const TARGETED_TEST_GROUPS = [
  {
    rule: 'summary_contract_test_gap',
    codePaths: [
      'dart_cli/lib/src/migrations/summary.dart',
      'dart_cli/lib/src/application/run_service.dart',
      'dart_cli/lib/src/cli.dart',
    ],
    testPaths: [
      'dart_cli/test/feature/migrations/summary_test.dart',
      'dart_cli/test/feature/cli/runner_test.dart',
      'dart_cli/test/unit/application/run_service_test.dart',
    ],
    message:
      'Summary/retry contract code changed without touching the summary or runner coverage that validates schema_version, retry_command, and failed-tags behavior.',
  },
  {
    rule: 'token_resolution_test_gap',
    codePaths: [
      'dart_cli/lib/src/config.dart',
      'dart_cli/lib/src/config/arg_parsers.dart',
      'dart_cli/lib/src/core/settings.dart',
      'dart_cli/lib/src/cli/settings_setup_command_handler.dart',
      'dart_cli/lib/src/config/validators.dart',
    ],
    testPaths: [
      'dart_cli/test/feature/cli/config_test.dart',
      'dart_cli/test/feature/cli/settings_flow_test.dart',
      'dart_cli/test/unit/core/settings_test.dart',
      'dart_cli/test/unit/cli/settings_setup_command_handler_test.dart',
      'dart_cli/test/unit/config/validators_test.dart',
    ],
    message:
      'Token resolution or settings profile code changed without updating the focused config/settings coverage that protects precedence and compatibility flags.',
  },
  {
    rule: 'release_selection_test_gap',
    codePaths: [
      'dart_cli/lib/src/migrations/selection.dart',
      'dart_cli/lib/src/migrations/engine.dart',
      'dart_cli/lib/src/migrations/tag_phase.dart',
      'dart_cli/lib/src/migrations/release_phase.dart',
    ],
    testPaths: [
      'dart_cli/test/feature/migrations/selection_test.dart',
      'dart_cli/test/unit/migrations/tag_phase_test.dart',
      'dart_cli/test/unit/migrations/release_phase_test.dart',
      'dart_cli/test/feature/migrations/engine_test.dart',
    ],
    message:
      'Release selection or migration phase code changed without updating the focused coverage that protects semver-only selection, tags-first flow, and resume semantics.',
  },
];

const CONTRACT_DOC_GROUPS = [
  {
    rule: 'summary_contract_docs_gap',
    codePaths: [
      'dart_cli/lib/src/migrations/summary.dart',
      'dart_cli/lib/src/application/run_service.dart',
      'dart_cli/lib/src/cli.dart',
    ],
    docPaths: [
      'README.md',
      'dart_cli/README.md',
      'website/docs/configuration/artifacts-and-sessions.md',
      'website/docs/guides/resume-and-retry.md',
      'website/docs/reference/file-locations.md',
      'website/docs/getting-started/first-migration.md',
      'website/docs/intro.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/configuration/artifacts-and-sessions.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/guides/resume-and-retry.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/reference/file-locations.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/getting-started/first-migration.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/intro.md',
    ],
    message:
      'Summary/retry contract code changed without updating the public docs that describe summary.json, failed-tags.txt, or resume behavior.',
  },
  {
    rule: 'token_contract_docs_gap',
    codePaths: [
      'dart_cli/lib/src/config.dart',
      'dart_cli/lib/src/config/arg_parsers.dart',
      'dart_cli/lib/src/core/settings.dart',
      'dart_cli/lib/src/cli/settings_setup_command_handler.dart',
    ],
    docPaths: [
      'README.md',
      'dart_cli/README.md',
      'website/docs/configuration/tokens-and-auth.md',
      'website/docs/configuration/settings-profiles.md',
      'website/docs/reference/environment-aliases.md',
      'website/docs/commands/migrate.md',
      'website/docs/commands/resume.md',
      'website/docs/commands/settings.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/configuration/tokens-and-auth.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/configuration/settings-profiles.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/reference/environment-aliases.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/commands/migrate.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/commands/resume.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/commands/settings.md',
    ],
    message:
      'Token/profile contract code changed without updating the public docs that describe token_env, token_plain, hidden overrides, or settings-profile behavior.',
  },
  {
    rule: 'selection_contract_docs_gap',
    codePaths: [
      'dart_cli/lib/src/migrations/selection.dart',
      'dart_cli/lib/src/migrations/engine.dart',
      'dart_cli/lib/src/migrations/tag_phase.dart',
      'dart_cli/lib/src/migrations/release_phase.dart',
      'dart_cli/lib/src/config.dart',
      'dart_cli/lib/src/config/arg_parsers.dart',
    ],
    docPaths: [
      'README.md',
      'dart_cli/README.md',
      'website/docs/commands/migrate.md',
      'website/docs/commands/resume.md',
      'website/docs/configuration/http-and-runtime.md',
      'website/docs/getting-started/quick-start.md',
      'website/docs/intro.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/commands/migrate.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/commands/resume.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/configuration/http-and-runtime.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/getting-started/quick-start.md',
      'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/intro.md',
    ],
    message:
      'Release-selection or skip-tags behavior changed without updating the public docs that describe semver-only selection, tags-first flow, or resume flags.',
  },
];

const SUMMARY_SCHEMA_VERSION_PATHS = new Set([
  'dart_cli/lib/src/cli.dart',
  'dart_cli/lib/src/migrations/summary.dart',
  'website/docs/configuration/artifacts-and-sessions.md',
  'website/docs/intro.md',
  'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/configuration/artifacts-and-sessions.md',
  'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/intro.md',
]);

const RETRY_COMMAND_PATHS = new Set([
  'dart_cli/lib/src/migrations/summary.dart',
  'dart_cli/lib/src/application/run_service.dart',
  'README.md',
  'website/docs/guides/resume-and-retry.md',
  'website/docs/getting-started/first-migration.md',
  'website/docs/intro.md',
  'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/guides/resume-and-retry.md',
  'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/getting-started/first-migration.md',
  'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/intro.md',
]);

const SEMVER_SELECTION_PATHS = new Set([
  'dart_cli/lib/src/migrations/selection.dart',
]);

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

function escapeRegex(text) {
  return text.replace(/[|\\{}()[\]^$+*?.]/g, '\\$&');
}

function branchPatternToRegex(pattern) {
  const regexPattern = pattern
    .split('*')
    .map((part) => escapeRegex(part))
    .join('.*')
    .replace(/\\\?/g, '.');
  return new RegExp(`^${regexPattern}$`);
}

export function matchesBranchPattern(branchName, pattern) {
  return branchPatternToRegex(pattern).test(branchName);
}

export function selectApplicableRule(branchName, rules) {
  const matchingRules = rules.filter((rule) => matchesBranchPattern(branchName, rule.pattern || ''));

  if (matchingRules.length === 0) {
    return null;
  }

  return matchingRules.sort((left, right) => (right.pattern || '').length - (left.pattern || '').length)[0];
}

function getContextName(context) {
  return context.__typename === 'CheckRun' ? context.name : context.context;
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

function parseAddedLines(patch = '') {
  const addedLines = [];
  const lines = patch.split('\n');
  let newLine = 0;

  for (const line of lines) {
    if (line.startsWith('@@')) {
      const match = line.match(/@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
      if (match) {
        newLine = Number(match[1]);
      }
      continue;
    }

    if (line.startsWith('+') && !line.startsWith('+++')) {
      addedLines.push({ line: newLine, text: line.slice(1) });
      newLine += 1;
      continue;
    }

    if (!line.startsWith('-') || line.startsWith('---')) {
      newLine += 1;
    }
  }

  return addedLines;
}

function getFirstCommentableLine(file) {
  const firstAddedLine = parseAddedLines(file.patch)[0];
  return firstAddedLine?.line ?? null;
}

function isPlaceholderSecret(text) {
  const normalized = text.toLowerCase();
  return [
    'example',
    'sample',
    'placeholder',
    'changeme',
    'your_',
    'dummy',
    'fake',
    'test-key',
  ].some((token) => normalized.includes(token));
}

function addFinding(findings, finding) {
  const key = `${finding.rule}:${finding.path}:${finding.line}`;
  const alreadyExists = findings.some(
    (current) => `${current.rule}:${current.path}:${current.line}` === key,
  );

  if (!alreadyExists) {
    findings.push(finding);
  }
}

function hasChangedExactPath(files, candidatePaths) {
  const candidateSet = new Set(candidatePaths);
  return files.some((file) => candidateSet.has(file.filename));
}

function findFirstChangedFile(files, candidatePaths) {
  const candidateSet = new Set(candidatePaths);
  return files.find((file) => candidateSet.has(file.filename)) ?? null;
}

function extractDartRegexPattern(text) {
  const regExpConstructorMatch = text.match(/RegExp\((?:r)?(['"])(.*?)\1\)/);
  if (regExpConstructorMatch) {
    return regExpConstructorMatch[2];
  }

  const rawLiteralMatch = text.match(/(?:^|[=:(\s])r(['"])(.*?)\1/);
  return rawLiteralMatch?.[2] ?? null;
}

function classifySemverPatternChange(text) {
  const pattern = extractDartRegexPattern(text);
  if (!pattern) {
    return 'unknown';
  }

  const normalizedPattern = pattern.replace(/\s+/g, '');
  if (STRICT_SEMVER_PATTERN_EQUIVALENTS.has(normalizedPattern)) {
    return 'strict';
  }

  const clearlyBroadenedChecks = [
    !normalizedPattern.startsWith('^'),
    !normalizedPattern.endsWith('$'),
    normalizedPattern.includes('.*'),
    normalizedPattern.includes('v?'),
    normalizedPattern.includes('(v)?'),
    normalizedPattern.includes('(?:v)?'),
  ];

  if (clearlyBroadenedChecks.some(Boolean)) {
    return 'broadened';
  }

  return 'unknown';
}

function buildSecretFindings(files) {
  const findings = [];

  for (const file of files) {
    const addedLines = parseAddedLines(file.patch);

    for (const addedLine of addedLines) {
      if (isPlaceholderSecret(addedLine.text)) {
        continue;
      }

      for (const pattern of SECRET_PATTERNS) {
        if (!pattern.regex.test(addedLine.text)) {
          continue;
        }

        addFinding(findings, {
          rule: pattern.rule,
          severity: 'blocking',
          path: file.filename,
          line: addedLine.line,
          message:
            'Potential secret or credential added in the diff. Move it to a secret store or environment variable.',
        });
      }
    }
  }

  return findings;
}

export function buildInvariantContractFindings(files) {
  const findings = [];

  for (const file of files) {
    const shouldCheckSchemaVersion = SUMMARY_SCHEMA_VERSION_PATHS.has(file.filename);
    const shouldCheckRetryCommand = RETRY_COMMAND_PATHS.has(file.filename);
    const shouldCheckSemverSelection = SEMVER_SELECTION_PATHS.has(file.filename);

    if (!shouldCheckSchemaVersion && !shouldCheckRetryCommand && !shouldCheckSemverSelection) {
      continue;
    }

    const addedLines = parseAddedLines(file.patch);

    for (const addedLine of addedLines) {
      const schemaVersionMatch =
        shouldCheckSchemaVersion && addedLine.text.match(/["']schema_version["']\s*:\s*(\d+)/);
      if (schemaVersionMatch && Number(schemaVersionMatch[1]) !== SUMMARY_SCHEMA_VERSION) {
        addFinding(findings, {
          rule: 'summary_schema_version_changed',
          severity: 'blocking',
          path: file.filename,
          line: addedLine.line,
          message: `summary.json must stay on schema_version ${SUMMARY_SCHEMA_VERSION} unless the project makes an explicit versioning decision.`,
        });
      }

      if (shouldCheckRetryCommand && addedLine.text.includes('retry_command') && addedLine.text.includes('gfrm migrate')) {
        addFinding(findings, {
          rule: 'retry_command_not_resume',
          severity: 'blocking',
          path: file.filename,
          line: addedLine.line,
          message: 'Retry guidance must keep using gfrm resume rather than telling users to rerun migrate.',
        });
      }

      if (shouldCheckSemverSelection && addedLine.text.includes('semverTagPattern')) {
        const semverPatternClassification = classifySemverPatternChange(addedLine.text);

        if (semverPatternClassification === 'broadened') {
          addFinding(findings, {
            rule: 'semver_selection_broadened',
            severity: 'blocking',
            path: file.filename,
            line: addedLine.line,
            message: 'Release selection must stay restricted to semver tags in the form vX.Y.Z.',
          });
        }

        if (semverPatternClassification === 'unknown') {
          addFinding(findings, {
            rule: 'review_semver_selection_change',
            severity: 'note',
            path: file.filename,
            line: addedLine.line,
            message:
              'semverTagPattern changed in a non-canonical way. Confirm it still matches only vX.Y.Z tags and preserves the expected capture groups.',
          });
        }
      }
    }
  }

  return findings;
}

export function buildDartTestFindings(files) {
  const changedTests = files.some((file) => file.filename.startsWith('dart_cli/test/'));
  const sourceFiles = files.filter(
    (file) =>
      file.filename.startsWith('dart_cli/lib/') &&
      file.filename.endsWith('.dart') &&
      typeof file.changes === 'number' &&
      getFirstCommentableLine(file) !== null,
  );

  if (changedTests || sourceFiles.length === 0) {
    return [];
  }

  const addedSourceFindings = sourceFiles
    .filter((file) => file.status === 'added' && file.changes >= 30)
    .slice(0, 3)
    .map((file) => ({
      rule: 'missing_dart_tests_for_new_source',
      severity: 'blocking',
      path: file.filename,
      line: getFirstCommentableLine(file),
      message:
        'New production Dart source was added without matching test coverage updates in dart_cli/test/**.',
    }));

  const modifiedSourceNotes = sourceFiles
    .filter((file) => file.status !== 'added' && file.changes >= 120)
    .slice(0, 2)
    .map((file) => ({
      rule: 'consider_dart_test_updates',
      severity: 'note',
      path: file.filename,
      line: getFirstCommentableLine(file),
      message:
        'Large Dart source changes landed without test updates in this PR. Confirm existing coverage still exercises this behavior.',
    }));

  return [...addedSourceFindings, ...modifiedSourceNotes];
}

export function buildTargetedCoverageFindings(files) {
  const findings = [];

  for (const group of TARGETED_TEST_GROUPS) {
    if (!hasChangedExactPath(files, group.codePaths) || hasChangedExactPath(files, group.testPaths)) {
      continue;
    }

    const anchorFile = findFirstChangedFile(files, group.codePaths);
    const line = anchorFile ? getFirstCommentableLine(anchorFile) : null;

    if (!anchorFile || line === null) {
      continue;
    }

    addFinding(findings, {
      rule: group.rule,
      severity: 'note',
      path: anchorFile.filename,
      line,
      message: group.message,
    });
  }

  return findings;
}

function toPtBrDocPath(path) {
  return path.replace(
    /^website\/docs\//,
    'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/',
  );
}

function toEnglishDocPath(path) {
  return path.replace(
    /^website\/i18n\/pt-BR\/docusaurus-plugin-content-docs\/current\//,
    'website/docs/',
  );
}

function buildDocsSyncFindings(files) {
  const changedPaths = new Set(files.map((file) => file.filename));
  const findings = [];

  for (const file of files) {
    const line = getFirstCommentableLine(file);

    if (line === null) {
      continue;
    }

    if (file.filename.startsWith('website/docs/')) {
      const ptPath = toPtBrDocPath(file.filename);
      if (!changedPaths.has(ptPath)) {
        addFinding(findings, {
          rule: 'missing_pt_br_doc_sync',
          severity: 'blocking',
          path: file.filename,
          line,
          message:
            'This docs change is missing the matching PT-BR translation update under website/i18n/pt-BR/...',
        });
      }
    }

    if (file.filename.startsWith('website/i18n/pt-BR/docusaurus-plugin-content-docs/current/')) {
      const enPath = toEnglishDocPath(file.filename);
      if (!changedPaths.has(enPath)) {
        addFinding(findings, {
          rule: 'missing_en_doc_sync',
          severity: 'blocking',
          path: file.filename,
          line,
          message: 'This PT-BR docs change is missing the matching English update under website/docs/...',
        });
      }
    }
  }

  return findings;
}

export function buildContractDocsFindings(files) {
  const findings = [];

  for (const group of CONTRACT_DOC_GROUPS) {
    if (!hasChangedExactPath(files, group.codePaths) || hasChangedExactPath(files, group.docPaths)) {
      continue;
    }

    const anchorFile = findFirstChangedFile(files, group.codePaths);
    const line = anchorFile ? getFirstCommentableLine(anchorFile) : null;

    if (!anchorFile || line === null) {
      continue;
    }

    addFinding(findings, {
      rule: group.rule,
      severity: 'note',
      path: anchorFile.filename,
      line,
      message: group.message,
    });
  }

  return findings;
}

async function fetchReviewRound(owner, repo) {
  const reviews = await paginate(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/reviews`);

  return (
    reviews.filter((review) => String(review.body || '').includes(AUTO_REVIEW_MARKER)).length + 1
  );
}

async function fetchRequiredCheckContexts(owner, repo, prNumber) {
  const query = `
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          baseRefName
          headRefOid
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup {
                  contexts(first: 100) {
                    nodes {
                      __typename
                      ... on CheckRun {
                        name
                        status
                        conclusion
                        detailsUrl
                      }
                      ... on StatusContext {
                        context
                        state
                        targetUrl
                      }
                    }
                  }
                }
              }
            }
          }
        }
        branchProtectionRules(first: 100) {
          nodes {
            pattern
            requiresStatusChecks
            requiredStatusCheckContexts
          }
        }
      }
    }
  `;

  const data = await githubGraphql(query, { owner, repo, number: prNumber });
  const pullRequest = data.repository.pullRequest;
  const branchProtectionRules = data.repository.branchProtectionRules.nodes.filter(
    (rule) => rule.requiresStatusChecks,
  );
  const selectedRule = selectApplicableRule(pullRequest.baseRefName, branchProtectionRules);

  return {
    pullRequest,
    requiredContexts: selectedRule?.requiredStatusCheckContexts ?? [],
    requiredContextSource: selectedRule ? 'branch_protection' : 'no_required_checks_detected',
  };
}

export function summarizeCheckState(contexts, requiredContexts, runId) {
  if (requiredContexts.length === 0) {
    return {
      checks_green: true,
      summary: { total: 0, passing: 0, pending: 0, failing: 0 },
    };
  }

  const requiredContextSet = new Set(requiredContexts);
  const selectedContexts = contexts.filter((context) => {
    const url = context.detailsUrl || context.targetUrl || '';

    if (url.includes(`/runs/${runId}`)) {
      return false;
    }

    return requiredContextSet.has(getContextName(context));
  });

  if (selectedContexts.length === 0) {
    return {
      checks_green: false,
      summary: { total: requiredContexts.length, passing: 0, pending: requiredContexts.length, failing: 0 },
    };
  }

  let passing = 0;
  let pending = 0;
  let failing = 0;

  for (const context of selectedContexts) {
    const status = context.status || context.state || '';
    const conclusion = context.conclusion || context.state || '';

    if (status === 'QUEUED' || status === 'IN_PROGRESS' || conclusion === 'PENDING') {
      pending += 1;
      continue;
    }

    if (conclusion === 'SUCCESS' || conclusion === 'NEUTRAL' || conclusion === 'SKIPPED') {
      passing += 1;
      continue;
    }

    failing += 1;
  }

  const missingRequiredContexts = Math.max(requiredContexts.length - selectedContexts.length, 0);

  return {
    checks_green: failing === 0 && pending === 0 && missingRequiredContexts === 0,
    summary: {
      total: requiredContexts.length,
      passing,
      pending: pending + missingRequiredContexts,
      failing,
    },
  };
}

async function fetchCheckState(owner, repo) {
  const { pullRequest, requiredContexts, requiredContextSource } = await fetchRequiredCheckContexts(
    owner,
    repo,
    PR_NUMBER,
  );
  const contexts =
    pullRequest.commits.nodes[0]?.commit?.statusCheckRollup?.contexts?.nodes?.filter(Boolean) ?? [];
  const summarized = summarizeCheckState(contexts, requiredContexts, RUN_ID);

  return {
    checks_green: summarized.checks_green,
    summary: summarized.summary,
    head_sha: pullRequest.headRefOid,
    required_contexts: requiredContexts,
    required_context_source: requiredContextSource,
  };
}

export function buildFallbackResult(errorMessage, prNumber = PR_NUMBER) {
  return {
    pr_number: prNumber,
    verdict: 'request_changes',
    blocking_findings: 1,
    non_blocking_findings: 0,
    findings: [],
    error: errorMessage,
    marker: AUTO_REVIEW_MARKER,
  };
}

async function persistResult(result) {
  await writeFile(REVIEW_RESULT_PATH, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
}

async function handleFatalError(error) {
  try {
    await persistResult(buildFallbackResult(error.message));
  } catch {}

  console.error(error);
}

export async function runReview() {
  assertRequiredEnv();

  const { owner, repo } = parseRepository(REPOSITORY);
  const [pullRequest, files] = await Promise.all([
    githubRequest(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}`),
    paginate(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/files`),
  ]);

  const [reviewRound, checkState] = await Promise.all([
    fetchReviewRound(owner, repo),
    fetchCheckState(owner, repo),
  ]);

  const findings = [
    ...buildSecretFindings(files),
    ...buildInvariantContractFindings(files),
    ...buildDartTestFindings(files),
    ...buildTargetedCoverageFindings(files),
    ...buildDocsSyncFindings(files),
    ...buildContractDocsFindings(files),
  ].sort((left, right) => left.path.localeCompare(right.path) || left.line - right.line);

  const blockingFindings = findings.filter((finding) => finding.severity === 'blocking').length;
  const nonBlockingFindings = findings.length - blockingFindings;
  const verdict = blockingFindings > 0 ? 'request_changes' : checkState.checks_green ? 'approve' : 'wait';

  return {
    pr_number: PR_NUMBER,
    head_sha: pullRequest.head.sha || checkState.head_sha,
    head_ref: pullRequest.head.ref,
    review_round: reviewRound,
    blocking_findings: blockingFindings,
    non_blocking_findings: nonBlockingFindings,
    checks_green: checkState.checks_green,
    checks_summary: checkState.summary,
    required_contexts: checkState.required_contexts,
    required_context_source: checkState.required_context_source,
    verdict,
    findings,
    marker: AUTO_REVIEW_MARKER,
  };
}

export async function main() {
  const result = await runReview();
  await persistResult(result);
  console.log(JSON.stringify(result, null, 2));
}

const isExecutedDirectly = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];

if (isExecutedDirectly) {
  main().catch(async (error) => {
    await handleFatalError(error);
    process.exit(1);
  });
}
