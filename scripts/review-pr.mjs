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
const ADDED_LINES_CACHE = new Map();

function expandDocPaths(paths) {
  const expanded = new Set();

  for (const path of paths) {
    expanded.add(path);

    if (path.startsWith('website/docs/')) {
      expanded.add(
        path.replace(
          /^website\/docs\//,
          'website/i18n/pt-BR/docusaurus-plugin-content-docs/current/',
        ),
      );
    }
  }

  return [...expanded];
}

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
    signalPatterns: [
      /schema_version/,
      /summary\.json/,
      /failed-tags\.txt/,
      /retry_command/,
      /gfrm resume/,
      /--settings-profile/,
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
    signalPatterns: [
      /token_env/,
      /token_plain/,
      /settings-profile/,
      /source-token/,
      /target-token/,
      /session-token-mode/,
      /SOURCE_TOKEN/,
      /TARGET_TOKEN/,
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
    signalPatterns: [
      /semverTagPattern/,
      /skip-tags/,
      /skipTag/,
      /selectedTags/,
      /skipTagMigration/,
    ],
    message:
      'Release selection or migration phase code changed without updating the focused coverage that protects semver-only selection, tags-first flow, and resume semantics.',
  },
  {
    rule: 'artifact_session_test_gap',
    codePaths: [
      'dart_cli/lib/src/application/run_paths.dart',
      'dart_cli/lib/src/application/run_service.dart',
      'dart_cli/lib/src/models/runtime_options.dart',
      'dart_cli/lib/src/cli/runtime_support.dart',
    ],
    testPaths: [
      'dart_cli/test/feature/cli/runner_test.dart',
      'dart_cli/test/feature/migrations/engine_test.dart',
      'dart_cli/test/unit/application/run_paths_test.dart',
      'dart_cli/test/unit/application/run_service_test.dart',
      'dart_cli/test/unit/models/runtime_options_test.dart',
      'dart_cli/test/unit/internal/private_entrypoints_test.dart',
    ],
    signalPatterns: [
      /migration-results/,
      /migration-log\.jsonl/,
      /checkpoints\/state\.jsonl/,
      /session-file/,
      /last-session\.json/,
      /resultsRootPath/,
      /runWorkdirPath/,
    ],
    message:
      'Artifact/session layout code changed without updating the focused coverage that protects migration-results paths, checkpoint locations, or session-file defaults.',
  },
  {
    rule: 'command_surface_test_gap',
    codePaths: [
      'dart_cli/lib/src/config/arg_parsers.dart',
      'dart_cli/lib/src/config.dart',
      'dart_cli/lib/src/cli.dart',
    ],
    testPaths: [
      'dart_cli/test/feature/cli/config_test.dart',
      'dart_cli/test/feature/cli/runner_test.dart',
      'dart_cli/test/unit/config/arg_parsers_test.dart',
    ],
    signalPatterns: [
      /addCommand\(command(?:Migrate|Resume|Demo|Setup|Settings)/,
      /Usage:\s*\$publicCommandName/,
      /settings <action>/,
      /demo-releases/,
      /demo-sleep-seconds/,
    ],
    message:
      'Public CLI command or usage surface changed without updating the focused parser/runner coverage that protects migrate, resume, demo, setup, and settings entrypoints.',
  },
  {
    rule: 'settings_actions_test_gap',
    codePaths: [
      'dart_cli/lib/src/config/arg_parsers.dart',
      'dart_cli/lib/src/core/settings.dart',
      'dart_cli/lib/src/cli/settings_setup_command_handler.dart',
      'dart_cli/lib/src/config.dart',
    ],
    testPaths: [
      'dart_cli/test/feature/cli/config_test.dart',
      'dart_cli/test/feature/cli/settings_flow_test.dart',
      'dart_cli/test/unit/cli/settings_setup_command_handler_test.dart',
      'dart_cli/test/unit/core/settings_test.dart',
    ],
    signalPatterns: [
      /settingsAction(?:Init|SetTokenEnv|SetTokenPlain|UnsetToken|Show)/,
      /set-token-env/,
      /set-token-plain/,
      /unset-token/,
      /settings show/i,
    ],
    message:
      'Settings command actions changed without updating the focused coverage that protects init, set-token-env, set-token-plain, unset-token, or show behavior.',
  },
  {
    rule: 'exit_code_contract_test_gap',
    codePaths: [
      'dart_cli/lib/src/cli.dart',
      'dart_cli/lib/src/application/run_service.dart',
      'dart_cli/lib/src/application/run_result.dart',
      'dart_cli/lib/src/cli/runtime_support.dart',
    ],
    testPaths: [
      'dart_cli/test/feature/cli/runner_test.dart',
      'dart_cli/test/unit/application/run_service_test.dart',
      'dart_cli/test/unit/internal/private_entrypoints_test.dart',
    ],
    signalPatterns: [
      /exitCode/,
      /RunStatus\.(?:success|partialFailure|validationFailure|runtimeFailure)/,
      /\breturn 0;/,
      /\breturn 1;/,
      /isSuccess/,
    ],
    message:
      'Exit-code or run-status mapping changed without updating the focused coverage that protects success, validation failure, partial failure, and runtime failure outcomes.',
  },
];

const RAW_EXCEPTION_PATTERNS = [
  { regex: /\bthrow\s+Exception\(/, message: 'Use project-specific exceptions (HttpRequestError, AuthenticationError, MigrationPhaseError) instead of generic Exception.' },
  { regex: /\bthrow\s+StateError\(/, message: 'Use MigrationPhaseError instead of StateError for engine-level failures.' },
  { regex: /\bthrow\s+ArgumentError\(/, message: 'Use MigrationPhaseError or a validation-specific exception instead of ArgumentError in production code.' },
  { regex: /\bthrow\s+UnimplementedError\(/, message: 'UnimplementedError should not ship in production code. Implement the method or remove the dead code path.' },
];

const SILENT_CATCH_PATTERN = /catch\s*\([^)]*\)\s*\{\s*\}/;

const PRINT_IN_PRODUCTION_PATTERN = /\bprint\(/;

const FLUTTER_TEST_GROUPS = [
  {
    rule: 'flutter_controller_test_gap',
    codePaths: [
      'gui/lib/src/runtime/run/gfrm_desktop_run_controller.dart',
      'gui/lib/src/runtime/run/desktop_run_controller_provider.dart',
    ],
    testPaths: [
      'gui/test/unit/runtime/run/gfrm_desktop_run_controller_test.dart',
      'gui/test/unit/runtime/run/desktop_run_controller_provider_test.dart',
    ],
    signalPatterns: [
      /DesktopRunController/,
      /DesktopRunSnapshot/,
      /StreamController/,
      /desktopRunControllerProvider/,
      /desktopRunSnapshotsProvider/,
    ],
    message:
      'Flutter controller or provider code changed without updating the corresponding test coverage.',
  },
  {
    rule: 'flutter_mapper_test_gap',
    codePaths: [
      'gui/lib/src/runtime/run/map_run_state_to_snapshot.dart',
      'gui/lib/src/runtime/run/map_desktop_run_start_request.dart',
    ],
    testPaths: [
      'gui/test/unit/runtime/run/map_run_state_to_snapshot_test.dart',
      'gui/test/unit/runtime/run/map_desktop_run_start_request_test.dart',
    ],
    signalPatterns: [
      /mapRunStateToSnapshot/,
      /mapDesktopRunStartRequest/,
    ],
    message:
      'Flutter mapper function changed without updating the corresponding test. Mapper functions must be tested as pure functions.',
  },
  {
    rule: 'flutter_theme_test_gap',
    codePaths: [
      'gui/lib/src/theme/gfrm_theme.dart',
      'gui/lib/src/theme/gfrm_colors.dart',
      'gui/lib/src/theme/gfrm_typography.dart',
    ],
    testPaths: [
      'gui/test/unit/theme/gfrm_theme_test.dart',
      'gui/test/widget/theme_test.dart',
    ],
    signalPatterns: [
      /GfrmColors/,
      /GfrmTypography/,
      /GfrmTheme/,
      /ColorScheme/,
      /ThemeData/,
    ],
    message:
      'Theme, color, or typography definitions changed without test coverage. Verify theme tokens render correctly.',
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
    docPaths: expandDocPaths([
      'README.md',
      'dart_cli/README.md',
      'website/docs/configuration/artifacts-and-sessions.md',
      'website/docs/guides/resume-and-retry.md',
      'website/docs/reference/file-locations.md',
      'website/docs/getting-started/first-migration.md',
      'website/docs/intro.md',
    ]),
    codeSignalPatterns: [
      /schema_version/,
      /summary\.json/,
      /failed-tags\.txt/,
      /retry_command/,
      /gfrm resume/,
      /--settings-profile/,
    ],
    docSignalPatterns: [
      /summary\.json/i,
      /failed-tags\.txt/i,
      /retry_command/i,
      /gfrm resume/i,
      /\bresume\b/i,
      /settings-profile/i,
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
    docPaths: expandDocPaths([
      'README.md',
      'dart_cli/README.md',
      'website/docs/configuration/tokens-and-auth.md',
      'website/docs/configuration/settings-profiles.md',
      'website/docs/reference/environment-aliases.md',
      'website/docs/commands/migrate.md',
      'website/docs/commands/resume.md',
      'website/docs/commands/settings.md',
    ]),
    codeSignalPatterns: [
      /token_env/,
      /token_plain/,
      /settings-profile/,
      /source-token/,
      /target-token/,
      /session-token-mode/,
      /SOURCE_TOKEN/,
      /TARGET_TOKEN/,
    ],
    docSignalPatterns: [
      /token_env/i,
      /token_plain/i,
      /settings-profile/i,
      /source-token/i,
      /target-token/i,
      /session token/i,
      /environment aliases/i,
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
    docPaths: expandDocPaths([
      'README.md',
      'dart_cli/README.md',
      'website/docs/commands/migrate.md',
      'website/docs/commands/resume.md',
      'website/docs/configuration/http-and-runtime.md',
      'website/docs/getting-started/quick-start.md',
      'website/docs/intro.md',
    ]),
    codeSignalPatterns: [
      /semverTagPattern/,
      /skip-tags/,
      /selectedTags/,
      /skipTagMigration/,
      /skipReleases/,
    ],
    docSignalPatterns: [
      /\bskip-tags\b/i,
      /\bsemver\b/i,
      /\btags-first\b/i,
      /\bresume\b/i,
      /release selection/i,
    ],
    message:
      'Release-selection or skip-tags behavior changed without updating the public docs that describe semver-only selection, tags-first flow, or resume flags.',
  },
  {
    rule: 'artifact_session_docs_gap',
    codePaths: [
      'dart_cli/lib/src/application/run_paths.dart',
      'dart_cli/lib/src/application/run_service.dart',
      'dart_cli/lib/src/models/runtime_options.dart',
      'dart_cli/lib/src/cli/runtime_support.dart',
    ],
    docPaths: expandDocPaths([
      'README.md',
      'dart_cli/README.md',
      'website/docs/configuration/artifacts-and-sessions.md',
      'website/docs/reference/file-locations.md',
      'website/docs/guides/resume-and-retry.md',
      'website/docs/getting-started/first-migration.md',
      'website/docs/intro.md',
    ]),
    codeSignalPatterns: [
      /migration-results/,
      /migration-log\.jsonl/,
      /checkpoints\/state\.jsonl/,
      /session-file/,
      /last-session\.json/,
      /resultsRootPath/,
      /runWorkdirPath/,
    ],
    docSignalPatterns: [
      /migration-results/i,
      /migration-log\.jsonl/i,
      /checkpoints\/state\.jsonl/i,
      /session-file/i,
      /last-session\.json/i,
      /file locations/i,
      /artifacts/i,
    ],
    message:
      'Artifact/session layout changed without updating the public docs that describe migration-results paths, file locations, or session-file defaults.',
  },
  {
    rule: 'command_surface_docs_gap',
    codePaths: [
      'dart_cli/lib/src/config/arg_parsers.dart',
      'dart_cli/lib/src/config.dart',
      'dart_cli/lib/src/cli.dart',
    ],
    docPaths: expandDocPaths([
      'README.md',
      'dart_cli/README.md',
      'website/docs/commands/migrate.md',
      'website/docs/commands/resume.md',
      'website/docs/commands/demo.md',
      'website/docs/commands/settings.md',
      'website/docs/getting-started/quick-start.md',
      'website/docs/getting-started/first-migration.md',
      'website/docs/guides/common-migrations.md',
      'website/docs/intro.md',
    ]),
    codeSignalPatterns: [
      /addCommand\(command(?:Migrate|Resume|Demo|Setup|Settings)/,
      /Usage:\s*\$publicCommandName/,
      /settings <action>/,
      /demo-releases/,
      /demo-sleep-seconds/,
    ],
    docSignalPatterns: [
      /gfrm (?:migrate|resume|demo|setup|settings)/i,
      /settings <action>/i,
      /demo-releases/i,
      /demo-sleep-seconds/i,
      /quick start/i,
    ],
    message:
      'Public CLI command or usage surface changed without updating the public docs that describe migrate, resume, demo, setup, or settings entrypoints.',
  },
  {
    rule: 'settings_actions_docs_gap',
    codePaths: [
      'dart_cli/lib/src/config/arg_parsers.dart',
      'dart_cli/lib/src/core/settings.dart',
      'dart_cli/lib/src/cli/settings_setup_command_handler.dart',
      'dart_cli/lib/src/config.dart',
    ],
    docPaths: expandDocPaths([
      'README.md',
      'dart_cli/README.md',
      'website/docs/commands/settings.md',
      'website/docs/configuration/tokens-and-auth.md',
      'website/docs/configuration/settings-profiles.md',
    ]),
    codeSignalPatterns: [
      /settingsAction(?:Init|SetTokenEnv|SetTokenPlain|UnsetToken|Show)/,
      /set-token-env/,
      /set-token-plain/,
      /unset-token/,
      /settings show/i,
    ],
    docSignalPatterns: [
      /set-token-env/i,
      /set-token-plain/i,
      /unset-token/i,
      /settings show/i,
      /gfrm settings init/i,
    ],
    message:
      'Settings command actions changed without updating the public docs that describe init, set-token-env, set-token-plain, unset-token, or show behavior.',
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

export function isBranchProtectionAccessDeniedError(error) {
  const message = String(error?.message || '');
  return message.includes('branchProtectionRules') && message.includes('Resource not accessible');
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
  if (ADDED_LINES_CACHE.has(patch)) {
    return ADDED_LINES_CACHE.get(patch);
  }

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

  ADDED_LINES_CACHE.set(patch, addedLines);
  return addedLines;
}

function getFirstCommentableLine(file) {
  if (!file.patch) {
    return 1;
  }

  const firstAddedLine = parseAddedLines(file.patch)[0];
  return firstAddedLine?.line ?? null;
}

function hasMissingPatch(file) {
  return (
    !file.patch &&
    file.status !== 'removed' &&
    typeof file.changes === 'number' &&
    file.changes > 0
  );
}

export function buildMissingPatchFindings(files) {
  const findings = [];

  for (const file of files) {
    if (!hasMissingPatch(file)) {
      continue;
    }

    addFinding(findings, {
      rule: 'missing_patch_manual_review_required',
      severity: 'blocking',
      path: file.filename,
      line: getFirstCommentableLine(file),
      message:
        'GitHub omitted patch data for this changed file. Automated inline checks cannot safely inspect this diff, so manual review is required before approval.',
    });
  }

  return findings;
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

function fileMatchesSignalPatterns(file, signalPatterns = []) {
  if (!Array.isArray(signalPatterns) || signalPatterns.length === 0) {
    return true;
  }

  return parseAddedLines(file.patch).some((addedLine) =>
    signalPatterns.some((pattern) => pattern.test(addedLine.text)),
  );
}

function findFirstSignalMatchedFile(files, candidatePaths, signalPatterns = []) {
  return (
    files.find((file) => candidatePaths.includes(file.filename) && fileMatchesSignalPatterns(file, signalPatterns)) ?? null
  );
}

function hasRelevantDocUpdate(files, candidatePaths, signalPatterns = []) {
  return files.some((file) => {
    if (!candidatePaths.includes(file.filename)) {
      return false;
    }

    if (!file.patch) {
      return true;
    }

    return fileMatchesSignalPatterns(file, signalPatterns);
  });
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

export function buildSecretFindings(files) {
  const findings = [];

  for (const file of files) {
    const addedLines = parseAddedLines(file.patch);

    for (const addedLine of addedLines) {
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
    if (hasChangedExactPath(files, group.testPaths)) {
      continue;
    }

    const anchorFile = findFirstSignalMatchedFile(files, group.codePaths, group.signalPatterns);
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
    const anchorFile = findFirstSignalMatchedFile(files, group.codePaths, group.codeSignalPatterns);
    const line = anchorFile ? getFirstCommentableLine(anchorFile) : null;

    if (!anchorFile || line === null) {
      continue;
    }

    if (hasRelevantDocUpdate(files, group.docPaths, group.docSignalPatterns ?? group.codeSignalPatterns ?? [])) {
      continue;
    }

    addFinding(findings, {
      rule: group.rule,
      severity: 'blocking',
      path: anchorFile.filename,
      line,
      message: group.message,
    });
  }

  return findings;
}

export function buildRawExceptionFindings(files) {
  const findings = [];
  const productionDartFiles = files.filter(
    (file) =>
      file.filename.startsWith('dart_cli/lib/') &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart'),
  );

  for (const file of productionDartFiles) {
    const addedLines = parseAddedLines(file.patch);

    for (const addedLine of addedLines) {
      for (const pattern of RAW_EXCEPTION_PATTERNS) {
        if (!pattern.regex.test(addedLine.text)) {
          continue;
        }

        addFinding(findings, {
          rule: 'raw_exception_in_production',
          severity: 'note',
          path: file.filename,
          line: addedLine.line,
          message: pattern.message,
        });
      }
    }
  }

  return findings;
}

export function buildSilentCatchFindings(files) {
  const findings = [];
  const dartFiles = files.filter(
    (file) =>
      (file.filename.startsWith('dart_cli/lib/') || file.filename.startsWith('gui/lib/')) &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart'),
  );

  for (const file of dartFiles) {
    const addedLines = parseAddedLines(file.patch);

    for (const addedLine of addedLines) {
      if (!SILENT_CATCH_PATTERN.test(addedLine.text)) {
        continue;
      }

      addFinding(findings, {
        rule: 'silent_catch_block',
        severity: 'blocking',
        path: file.filename,
        line: addedLine.line,
        message:
          'Empty catch block silently swallows errors. Log with context or rethrow.',
      });
    }
  }

  return findings;
}

export function buildPrintInProductionFindings(files) {
  const findings = [];
  const productionFiles = files.filter(
    (file) =>
      (file.filename.startsWith('dart_cli/lib/') || file.filename.startsWith('gui/lib/')) &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart') &&
      !file.filename.includes('/test/'),
  );

  for (const file of productionFiles) {
    const addedLines = parseAddedLines(file.patch);

    for (const addedLine of addedLines) {
      if (!PRINT_IN_PRODUCTION_PATTERN.test(addedLine.text)) {
        continue;
      }

      // Ignore lines that are clearly comments
      if (addedLine.text.trimStart().startsWith('//')) {
        continue;
      }

      addFinding(findings, {
        rule: 'print_in_production',
        severity: 'note',
        path: file.filename,
        line: addedLine.line,
        message:
          'Use the logging infrastructure instead of print() in production code.',
      });
    }
  }

  return findings;
}

export function buildFlutterTestFindings(files) {
  const changedFlutterTests = files.some((file) => file.filename.startsWith('gui/test/'));
  const sourceFiles = files.filter(
    (file) =>
      file.filename.startsWith('gui/lib/') &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart') &&
      typeof file.changes === 'number' &&
      getFirstCommentableLine(file) !== null,
  );

  if (changedFlutterTests || sourceFiles.length === 0) {
    return [];
  }

  const addedSourceFindings = sourceFiles
    .filter((file) => file.status === 'added' && file.changes >= 30)
    .slice(0, 3)
    .map((file) => ({
      rule: 'missing_flutter_tests_for_new_source',
      severity: 'blocking',
      path: file.filename,
      line: getFirstCommentableLine(file),
      message:
        'New Flutter production source was added without matching test coverage updates in gui/test/**.',
    }));

  const modifiedSourceNotes = sourceFiles
    .filter((file) => file.status !== 'added' && file.changes >= 120)
    .slice(0, 2)
    .map((file) => ({
      rule: 'consider_flutter_test_updates',
      severity: 'note',
      path: file.filename,
      line: getFirstCommentableLine(file),
      message:
        'Large Flutter source changes landed without test updates in this PR. Confirm existing coverage still exercises this behavior.',
    }));

  return [...addedSourceFindings, ...modifiedSourceNotes];
}

export function buildFlutterTargetedCoverageFindings(files) {
  const findings = [];

  for (const group of FLUTTER_TEST_GROUPS) {
    if (hasChangedExactPath(files, group.testPaths)) {
      continue;
    }

    const anchorFile = findFirstSignalMatchedFile(files, group.codePaths, group.signalPatterns);
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

const MULTI_CLASS_PATTERN = /^(?:abstract\s+)?(?:final\s+)?(?:base\s+)?(?:sealed\s+)?(?:mixin\s+)?class\s+\w+/;

const LOGIC_IN_BUILD_PATTERNS = [
  { regex: /\bawait\s+/, message: 'Async operation inside build() method — move to controller or provider.' },
  { regex: /\bhttp\.\w+\(/, message: 'HTTP call inside build() method — move to controller or service layer.' },
  { regex: /\bFile\(/, message: 'File I/O inside build() method — move to controller or service layer.' },
  { regex: /\bProcess\.run\(/, message: 'Process execution inside build() method — move to controller or service layer.' },
];

const GOD_CLASS_LINE_THRESHOLD = 500;
const LONG_METHOD_LINE_THRESHOLD = 120;

export function buildMultiClassFindings(files) {
  const findings = [];
  const dartFiles = files.filter(
    (file) =>
      (file.filename.startsWith('dart_cli/lib/') || file.filename.startsWith('gui/lib/')) &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart') &&
      !file.filename.endsWith('.freezed.dart'),
  );

  for (const file of dartFiles) {
    const addedLines = parseAddedLines(file.patch);
    const classDeclarations = addedLines.filter((line) => MULTI_CLASS_PATTERN.test(line.text.trim()));

    if (classDeclarations.length > 1) {
      addFinding(findings, {
        rule: 'multi_class_single_file',
        severity: 'blocking',
        path: file.filename,
        line: classDeclarations[1].line,
        message:
          `Multiple class declarations added to a single file. Prefer one class per file for SRP compliance. Found ${classDeclarations.length} class declarations in new lines.`,
      });
    }
  }

  return findings;
}

export function buildLogicInBuildFindings(files) {
  const findings = [];
  const flutterFiles = files.filter(
    (file) =>
      file.filename.startsWith('gui/lib/') &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart'),
  );

  for (const file of flutterFiles) {
    const addedLines = parseAddedLines(file.patch);
    let insideBuild = false;
    let braceDepth = 0;

    for (const addedLine of addedLines) {
      const trimmed = addedLine.text.trim();

      if (/Widget\s+build\s*\(/.test(trimmed) || /\@override\s*$/.test(trimmed)) {
        // Heuristic: next method-like line after @override in a widget is likely build()
      }

      if (/Widget\s+build\s*\(/.test(trimmed)) {
        insideBuild = true;
        braceDepth = 0;
      }

      if (insideBuild) {
        braceDepth += (trimmed.match(/\{/g) || []).length;
        braceDepth -= (trimmed.match(/\}/g) || []).length;

        if (braceDepth <= 0 && trimmed.includes('}')) {
          insideBuild = false;
          continue;
        }

        for (const pattern of LOGIC_IN_BUILD_PATTERNS) {
          if (pattern.regex.test(trimmed) && !trimmed.startsWith('//')) {
            addFinding(findings, {
              rule: 'logic_in_build_method',
              severity: 'blocking',
              path: file.filename,
              line: addedLine.line,
              message: pattern.message,
            });
          }
        }
      }
    }
  }

  return findings;
}

export function buildGodClassFindings(files) {
  const findings = [];
  const dartFiles = files.filter(
    (file) =>
      (file.filename.startsWith('dart_cli/lib/') || file.filename.startsWith('gui/lib/')) &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart') &&
      !file.filename.endsWith('.freezed.dart') &&
      file.status === 'added' &&
      typeof file.additions === 'number',
  );

  for (const file of dartFiles) {
    if (file.additions > GOD_CLASS_LINE_THRESHOLD) {
      const line = getFirstCommentableLine(file);
      if (line !== null) {
        addFinding(findings, {
          rule: 'god_class_new_file',
          severity: 'blocking',
          path: file.filename,
          line,
          message:
            `New file has ${file.additions} lines — exceeds the ${GOD_CLASS_LINE_THRESHOLD}-line threshold. Break into smaller, focused classes following SRP.`,
        });
      }
    }
  }

  return findings;
}

export function buildLongMethodFindings(files) {
  const findings = [];
  const dartFiles = files.filter(
    (file) =>
      (file.filename.startsWith('dart_cli/lib/') || file.filename.startsWith('gui/lib/')) &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart'),
  );

  for (const file of dartFiles) {
    const addedLines = parseAddedLines(file.patch);
    let methodStartLine = null;
    let methodName = null;
    let braceDepth = 0;
    let methodLineCount = 0;

    for (const addedLine of addedLines) {
      const trimmed = addedLine.text.trim();

      // Detect method/function declarations
      const methodMatch = trimmed.match(/(?:Future|void|bool|int|String|double|List|Map|Set|dynamic|\w+)\s+(\w+)\s*[(<]/);
      if (methodMatch && !trimmed.startsWith('//') && !trimmed.startsWith('class ')) {
        if (methodStartLine !== null && methodLineCount > LONG_METHOD_LINE_THRESHOLD) {
          addFinding(findings, {
            rule: 'long_method',
            severity: 'note',
            path: file.filename,
            line: methodStartLine,
            message:
              `Method '${methodName}' spans ${methodLineCount}+ added lines — exceeds ${LONG_METHOD_LINE_THRESHOLD}-line guideline. Consider extracting sub-operations.`,
          });
        }

        methodStartLine = addedLine.line;
        methodName = methodMatch[1];
        braceDepth = 0;
        methodLineCount = 0;
      }

      if (methodStartLine !== null) {
        methodLineCount += 1;
        braceDepth += (trimmed.match(/\{/g) || []).length;
        braceDepth -= (trimmed.match(/\}/g) || []).length;

        if (braceDepth <= 0 && methodLineCount > 1 && trimmed.includes('}')) {
          if (methodLineCount > LONG_METHOD_LINE_THRESHOLD) {
            addFinding(findings, {
              rule: 'long_method',
              severity: 'note',
              path: file.filename,
              line: methodStartLine,
              message:
                `Method '${methodName}' spans ${methodLineCount} added lines — exceeds ${LONG_METHOD_LINE_THRESHOLD}-line guideline. Consider extracting sub-operations.`,
            });
          }
          methodStartLine = null;
          methodName = null;
          methodLineCount = 0;
        }
      }
    }
  }

  return findings;
}

export function buildSetStateFindings(files) {
  const findings = [];
  const flutterFiles = files.filter(
    (file) =>
      file.filename.startsWith('gui/lib/') &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart'),
  );

  for (const file of flutterFiles) {
    const addedLines = parseAddedLines(file.patch);

    for (const addedLine of addedLines) {
      const trimmed = addedLine.text.trim();

      if (trimmed.startsWith('//')) {
        continue;
      }

      if (/\bsetState\s*\(/.test(trimmed)) {
        addFinding(findings, {
          rule: 'set_state_in_riverpod_project',
          severity: 'blocking',
          path: file.filename,
          line: addedLine.line,
          message:
            'setState() detected in a Riverpod project. Use Riverpod providers and controllers for state management instead of StatefulWidget.',
        });
      }
    }
  }

  return findings;
}

export function buildDirectDependencyFindings(files) {
  const findings = [];
  const engineFiles = files.filter(
    (file) =>
      file.filename.startsWith('dart_cli/lib/src/migrations/') &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart'),
  );

  for (const file of engineFiles) {
    const addedLines = parseAddedLines(file.patch);

    for (const addedLine of addedLines) {
      const trimmed = addedLine.text.trim();

      if (trimmed.startsWith('//')) {
        continue;
      }

      // Detect direct HTTP or provider imports in engine layer
      if (/import\s+['"].*\/providers\/(?:github|gitlab|bitbucket)\.dart['"]/.test(trimmed)) {
        addFinding(findings, {
          rule: 'engine_imports_provider_directly',
          severity: 'blocking',
          path: file.filename,
          line: addedLine.line,
          message:
            'Engine layer imports a concrete provider adapter directly. Engine must depend on abstractions (interfaces), not concrete provider implementations. Use dependency injection via the ProviderRegistry.',
        });
      }

      // Detect direct HTTP calls in engine layer
      if (/\b(?:http\.get|http\.post|http\.put|http\.delete|requestJson|requestStatus|downloadFile)\s*\(/.test(trimmed)) {
        addFinding(findings, {
          rule: 'engine_makes_http_calls',
          severity: 'blocking',
          path: file.filename,
          line: addedLine.line,
          message:
            'Direct HTTP call in engine layer. All forge API interactions must go through provider adapters to maintain clean architecture boundaries.',
        });
      }
    }
  }

  return findings;
}

export function buildGuiBoundaryFindings(files) {
  const findings = [];
  const guiFiles = files.filter(
    (file) =>
      file.filename.startsWith('gui/lib/') &&
      file.filename.endsWith('.dart') &&
      !file.filename.endsWith('.g.dart'),
  );

  for (const file of guiFiles) {
    const addedLines = parseAddedLines(file.patch);

    for (const addedLine of addedLines) {
      const trimmed = addedLine.text.trim();

      if (trimmed.startsWith('//')) {
        continue;
      }

      // GUI importing CLI-specific code
      if (/import\s+['"].*gfrm_dart\/src\/cli\.dart['"]/.test(trimmed) ||
          /import\s+['"].*gfrm_dart\/src\/config\/arg_parsers\.dart['"]/.test(trimmed)) {
        addFinding(findings, {
          rule: 'gui_imports_cli_internals',
          severity: 'blocking',
          path: file.filename,
          line: addedLine.line,
          message:
            'GUI imports CLI-specific code (cli.dart or arg_parsers). GUI must use the application layer and runtime contracts, not CLI entry points.',
        });
      }
    }
  }

  return findings;
}

async function fetchReviewRound(owner, repo) {
  const reviews = await paginate(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/reviews`);

  return (
    reviews.filter((review) => String(review.body || '').includes(AUTO_REVIEW_MARKER)).length + 1
  );
}

export function selectRequiredContexts(baseRefName, branchProtectionRules, { branchProtectionAvailable = true } = {}) {
  if (!branchProtectionAvailable) {
    return {
      requiredContexts: [],
      requiredContextSource: 'branch_protection_unavailable',
    };
  }

  const selectedRule = selectApplicableRule(baseRefName, branchProtectionRules);
  return {
    requiredContexts: selectedRule?.requiredStatusCheckContexts ?? [],
    requiredContextSource: selectedRule ? 'branch_protection' : 'no_required_checks_detected',
  };
}

async function fetchRequiredCheckContexts(owner, repo, prNumber) {
  const pullRequestQuery = `
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
      }
    }
  `;

  const branchProtectionQuery = `
    query($owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
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

  const pullRequestData = await githubGraphql(pullRequestQuery, { owner, repo, number: prNumber });
  const pullRequest = pullRequestData.repository.pullRequest;

  try {
    const branchProtectionData = await githubGraphql(branchProtectionQuery, { owner, repo });
    const branchProtectionRules = branchProtectionData.repository.branchProtectionRules.nodes.filter(
      (rule) => rule.requiresStatusChecks,
    );
    const selectedContexts = selectRequiredContexts(pullRequest.baseRefName, branchProtectionRules);

    return {
      pullRequest,
      requiredContexts: selectedContexts.requiredContexts,
      requiredContextSource: selectedContexts.requiredContextSource,
    };
  } catch (error) {
    if (!isBranchProtectionAccessDeniedError(error)) {
      throw error;
    }

    const selectedContexts = selectRequiredContexts(pullRequest.baseRefName, [], {
      branchProtectionAvailable: false,
    });

    return {
      pullRequest,
      requiredContexts: selectedContexts.requiredContexts,
      requiredContextSource: selectedContexts.requiredContextSource,
    };
  }
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
    ...buildMissingPatchFindings(files),
    ...buildSecretFindings(files),
    ...buildInvariantContractFindings(files),
    ...buildRawExceptionFindings(files),
    ...buildSilentCatchFindings(files),
    ...buildPrintInProductionFindings(files),
    ...buildMultiClassFindings(files),
    ...buildLogicInBuildFindings(files),
    ...buildGodClassFindings(files),
    ...buildLongMethodFindings(files),
    ...buildSetStateFindings(files),
    ...buildDirectDependencyFindings(files),
    ...buildGuiBoundaryFindings(files),
    ...buildDartTestFindings(files),
    ...buildTargetedCoverageFindings(files),
    ...buildFlutterTestFindings(files),
    ...buildFlutterTargetedCoverageFindings(files),
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
