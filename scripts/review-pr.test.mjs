import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildContractDocsFindings,
  buildDartTestFindings,
  buildInvariantContractFindings,
  buildMissingPatchFindings,
  buildSecretFindings,
  isBranchProtectionAccessDeniedError,
  selectRequiredContexts,
  buildTargetedCoverageFindings,
  selectApplicableRule,
  summarizeCheckState,
} from './review-pr.mjs';

function buildPatchedFile({ filename, status = 'modified', changes = 1, patch }) {
  return {
    filename,
    status,
    changes,
    patch,
  };
}

test('selectApplicableRule prefers the most specific branch pattern', () => {
  const selectedRule = selectApplicableRule('release/1.2.3', [
    { pattern: '*' },
    { pattern: 'release/*' },
    { pattern: 'release/1.*' },
  ]);

  assert.equal(selectedRule?.pattern, 'release/1.*');
});

test('selectRequiredContexts reports unavailable branch protection when access is forbidden', () => {
  const selected = selectRequiredContexts('main', [], { branchProtectionAvailable: false });

  assert.deepEqual(selected, {
    requiredContexts: [],
    requiredContextSource: 'branch_protection_unavailable',
  });
});

test('selectRequiredContexts returns required contexts from the matching rule', () => {
  const selected = selectRequiredContexts('main', [
    {
      pattern: 'main',
      requiredStatusCheckContexts: ['Quality Checks', 'Automated PR Review'],
    },
  ]);

  assert.deepEqual(selected, {
    requiredContexts: ['Quality Checks', 'Automated PR Review'],
    requiredContextSource: 'branch_protection',
  });
});

test('isBranchProtectionAccessDeniedError detects forbidden branch protection reads', () => {
  assert.equal(
    isBranchProtectionAccessDeniedError(
      new Error(
        'GitHub GraphQL error: [{"path":["repository","branchProtectionRules"],"message":"Resource not accessible by personal access token"}]',
      ),
    ),
    true,
  );
  assert.equal(isBranchProtectionAccessDeniedError(new Error('GitHub GraphQL error: unrelated failure')), false);
});

test('summarizeCheckState ignores failing optional contexts when required checks pass', () => {
  const result = summarizeCheckState(
    [
      {
        __typename: 'CheckRun',
        name: 'Quality Checks',
        status: 'COMPLETED',
        conclusion: 'SUCCESS',
        detailsUrl: 'https://github.com/example/repo/actions/runs/100',
      },
      {
        __typename: 'CheckRun',
        name: 'Optional Smoke',
        status: 'COMPLETED',
        conclusion: 'FAILURE',
        detailsUrl: 'https://github.com/example/repo/actions/runs/101',
      },
    ],
    ['Quality Checks'],
    '999',
  );

  assert.equal(result.checks_green, true);
  assert.deepEqual(result.summary, {
    total: 1,
    passing: 1,
    pending: 0,
    failing: 0,
  });
});

test('summarizeCheckState treats missing required contexts as pending', () => {
  const result = summarizeCheckState([], ['Quality Checks'], '999');

  assert.equal(result.checks_green, false);
  assert.deepEqual(result.summary, {
    total: 1,
    passing: 0,
    pending: 1,
    failing: 0,
  });
});

test('summarizeCheckState allows approval when no required checks are configured', () => {
  const result = summarizeCheckState(
    [
      {
        __typename: 'CheckRun',
        name: 'Optional Smoke',
        status: 'COMPLETED',
        conclusion: 'FAILURE',
        detailsUrl: 'https://github.com/example/repo/actions/runs/101',
      },
    ],
    [],
    '999',
  );

  assert.equal(result.checks_green, true);
  assert.deepEqual(result.summary, {
    total: 0,
    passing: 0,
    pending: 0,
    failing: 0,
  });
});

test('buildDartTestFindings blocks new production Dart files without tests', () => {
  const findings = buildDartTestFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/new_engine.dart',
      status: 'added',
      changes: 48,
      patch: '@@ -0,0 +1,3 @@\n+class NewEngine {}\n+\n+void run() {}',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].severity, 'blocking');
  assert.equal(findings[0].rule, 'missing_dart_tests_for_new_source');
});

test('buildDartTestFindings still reports missing-test risk when GitHub omits patch', () => {
  const findings = buildDartTestFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/new_engine.dart',
      status: 'added',
      changes: 48,
      patch: undefined,
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].severity, 'blocking');
  assert.equal(findings[0].line, 1);
});

test('buildMissingPatchFindings blocks changed files when GitHub omits patch data', () => {
  const findings = buildMissingPatchFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/engine.dart',
      status: 'modified',
      changes: 27,
      patch: undefined,
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'missing_patch_manual_review_required');
  assert.equal(findings[0].severity, 'blocking');
  assert.equal(findings[0].line, 1);
});

test('buildSecretFindings does not suppress realistic token-like values with placeholder words', () => {
  const findings = buildSecretFindings([
    buildPatchedFile({
      filename: 'README.md',
      status: 'modified',
      changes: 2,
      patch: '@@ -1,1 +1,1 @@\n+export GH_TOKEN=ghp_example12345678901234567890',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'secret_github_token');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildDartTestFindings emits only a note for large modified Dart files without tests', () => {
  const findings = buildDartTestFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/existing_engine.dart',
      status: 'modified',
      changes: 180,
      patch: '@@ -10,3 +10,3 @@\n+refactor();',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].severity, 'note');
  assert.equal(findings[0].rule, 'consider_dart_test_updates');
});

test('buildDartTestFindings stays quiet when tests already changed in the PR', () => {
  const findings = buildDartTestFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/new_engine.dart',
      status: 'added',
      changes: 48,
      patch: '@@ -0,0 +1,3 @@\n+class NewEngine {}\n+\n+void run() {}',
    }),
    buildPatchedFile({
      filename: 'dart_cli/test/unit/new_engine_test.dart',
      status: 'added',
      changes: 24,
      patch: '@@ -0,0 +1,2 @@\n+void main() {}\n+',
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildInvariantContractFindings blocks schema_version drift', () => {
  const findings = buildInvariantContractFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/cli.dart',
      changes: 12,
      patch: "@@ -1,1 +1,1 @@\n+  'schema_version': 3,",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'summary_schema_version_changed');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildInvariantContractFindings blocks retry_command drift to migrate', () => {
  const findings = buildInvariantContractFindings([
    buildPatchedFile({
      filename: 'website/docs/guides/resume-and-retry.md',
      changes: 8,
      patch: '@@ -1,1 +1,1 @@\n+retry_command: gfrm migrate --tags-file failed-tags.txt',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'retry_command_not_resume');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildInvariantContractFindings blocks broader release-selection regex', () => {
  const findings = buildInvariantContractFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/selection.dart',
      changes: 4,
      patch: "@@ -1,1 +1,1 @@\n+static final RegExp semverTagPattern = RegExp(r'^(v)?(\\d+)\\.(\\d+)\\.(\\d+)$');",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'semver_selection_broadened');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildInvariantContractFindings blocks semver regex without anchors', () => {
  const findings = buildInvariantContractFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/selection.dart',
      changes: 4,
      patch:
        "@@ -1,1 +1,1 @@\n+static final RegExp semverTagPattern = RegExp(r'v(\\d+)\\.(\\d+)\\.(\\d+)');",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'semver_selection_broadened');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildInvariantContractFindings accepts equivalent strict semver regex refactors', () => {
  const findings = buildInvariantContractFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/selection.dart',
      changes: 4,
      patch:
        "@@ -1,1 +1,1 @@\n+static final RegExp semverTagPattern = RegExp(r'^v([0-9]+)\\.([0-9]+)\\.([0-9]+)$');",
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildInvariantContractFindings downgrades non-canonical semver regex changes to a note', () => {
  const findings = buildInvariantContractFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/selection.dart',
      changes: 4,
      patch:
        "@@ -1,1 +1,1 @@\n+static final RegExp semverTagPattern = RegExp('^v(\\\\d+)\\\\.(\\\\d+)\\\\.(\\\\d+)\$');",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'review_semver_selection_change');
  assert.equal(findings[0].severity, 'note');
});

test('buildInvariantContractFindings downgrades equivalent constructor refactors to a note when shape is unclear', () => {
  const findings = buildInvariantContractFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/selection.dart',
      changes: 4,
      patch:
        "@@ -1,1 +1,1 @@\n+static final RegExp semverTagPattern = RegExp(String.raw`^v(\\d+)\\.(\\d+)\\.(\\d+)$`);",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'review_semver_selection_change');
  assert.equal(findings[0].severity, 'note');
});

test('buildInvariantContractFindings ignores reviewer self-tests with forbidden example strings', () => {
  const findings = buildInvariantContractFindings([
    buildPatchedFile({
      filename: 'scripts/review-pr.test.mjs',
      changes: 22,
      patch:
        '@@ -1,1 +1,3 @@\n+assert.equal(result[\'schema_version\'], 3);\n+retry_command: gfrm migrate --tags-file failed-tags.txt\n+static final RegExp semverTagPattern = RegExp(r\'^(v)?(\\\\d+)\\.(\\\\d+)\\.(\\\\d+)$\');',
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildTargetedCoverageFindings adds a note when token resolution changes lack focused tests', () => {
  const findings = buildTargetedCoverageFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/config.dart',
      changes: 18,
      patch: '@@ -1,1 +1,1 @@\n+final String settingsProfileRequested = _optionalString(args, \'settings-profile\');',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'token_resolution_test_gap');
  assert.equal(findings[0].severity, 'note');
});

test('buildTargetedCoverageFindings ignores internal refactors without contract-facing signals', () => {
  const findings = buildTargetedCoverageFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/application/run_service.dart',
      changes: 10,
      patch: "@@ -14,0 +15,2 @@\n+import 'run_paths.dart';\n+final PreparedPaths paths = createRunPaths(runtimeOptions);",
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildTargetedCoverageFindings stays quiet when matching focused tests changed', () => {
  const findings = buildTargetedCoverageFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/config.dart',
      changes: 18,
      patch: '@@ -1,1 +1,1 @@\n+final String settingsProfileRequested = _optionalString(args, \'settings-profile\');',
    }),
    buildPatchedFile({
      filename: 'dart_cli/test/feature/cli/config_test.dart',
      status: 'added',
      changes: 12,
      patch: '@@ -0,0 +1,1 @@\n+test(\'config precedence\', () {});',
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildContractDocsFindings blocks summary contract changes without docs sync', () => {
  const findings = buildContractDocsFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/summary.dart',
      changes: 14,
      patch: '@@ -1,1 +1,1 @@\n+parts.addAll(<String>[\'--settings-profile\', options.settingsProfile]);',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'summary_contract_docs_gap');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildContractDocsFindings still blocks when only unrelated docs in the group changed', () => {
  const findings = buildContractDocsFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/summary.dart',
      changes: 14,
      patch: "@@ -1,1 +1,1 @@\n+const String retryCommand = 'gfrm resume --session migration-results/latest/session.json';",
    }),
    buildPatchedFile({
      filename: 'website/docs/intro.md',
      changes: 2,
      patch: '@@ -1,1 +1,1 @@\n+Small copy edit for onboarding text.',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'summary_contract_docs_gap');
});

test('buildContractDocsFindings stays quiet when matching docs change includes contract signal', () => {
  const findings = buildContractDocsFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/summary.dart',
      changes: 14,
      patch: "@@ -1,1 +1,1 @@\n+const String retryCommand = 'gfrm resume --session migration-results/latest/session.json';",
    }),
    buildPatchedFile({
      filename: 'website/docs/guides/resume-and-retry.md',
      changes: 4,
      patch: '@@ -1,1 +1,1 @@\n+Use gfrm resume from the retry_command saved in summary.json.',
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildContractDocsFindings ignores internal refactors without contract-facing signals', () => {
  const findings = buildContractDocsFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/application/run_service.dart',
      changes: 6,
      patch: "@@ -14,0 +15,2 @@\n+import 'run_paths.dart';\n+final PreparedPaths paths = createRunPaths(runtimeOptions);",
    }),
  ]);

  assert.deepEqual(findings, []);
});
