import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildContractDocsFindings,
  buildDartTestFindings,
  buildDirectDependencyFindings,
  buildFlutterTargetedCoverageFindings,
  buildFlutterTestFindings,
  buildGodClassFindings,
  buildGuiBoundaryFindings,
  buildInvariantContractFindings,
  buildLogicInBuildFindings,
  buildLongMethodFindings,
  buildMissingPatchFindings,
  buildMultiClassFindings,
  buildPrintInProductionFindings,
  buildRawExceptionFindings,
  buildSecretFindings,
  buildSetStateFindings,
  buildSilentCatchFindings,
  buildTargetedCoverageFindings,
  isBranchProtectionAccessDeniedError,
  selectApplicableRule,
  selectRequiredContexts,
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

test('buildTargetedCoverageFindings adds a note when artifact/session layout changes lack focused tests', () => {
  const findings = buildTargetedCoverageFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/application/run_paths.dart',
      changes: 12,
      patch: "@@ -1,1 +1,1 @@\n+return '$cwd/migration-results';",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'artifact_session_test_gap');
  assert.equal(findings[0].severity, 'note');
});

test('buildTargetedCoverageFindings adds a note when CLI command surface changes lack focused tests', () => {
  const findings = buildTargetedCoverageFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/config/arg_parsers.dart',
      changes: 14,
      patch: "@@ -1,1 +1,1 @@\n+    parser.addCommand(commandDemo, _buildDemoParser());",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'command_surface_test_gap');
  assert.equal(findings[0].severity, 'note');
});

test('buildTargetedCoverageFindings adds a note when settings actions change lack focused tests', () => {
  const findings = buildTargetedCoverageFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/cli/settings_setup_command_handler.dart',
      changes: 18,
      patch: "@@ -1,1 +1,1 @@\n+if (options.action == settingsActionUnsetToken) return _runUnsetToken(options);",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'settings_actions_test_gap');
  assert.equal(findings[0].severity, 'note');
});

test('buildTargetedCoverageFindings adds a note when exit code mapping changes lack focused tests', () => {
  const findings = buildTargetedCoverageFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/application/run_result.dart',
      changes: 10,
      patch: '@@ -1,1 +1,1 @@\n+  final int exitCode;',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'exit_code_contract_test_gap');
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

test('buildContractDocsFindings blocks artifact/session changes without docs sync', () => {
  const findings = buildContractDocsFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/application/run_paths.dart',
      changes: 16,
      patch: "@@ -1,1 +1,1 @@\n+return '$cwd/migration-results';",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'artifact_session_docs_gap');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildContractDocsFindings stays quiet for artifact/session changes when matching docs change includes contract signal', () => {
  const findings = buildContractDocsFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/application/run_paths.dart',
      changes: 16,
      patch: "@@ -1,1 +1,1 @@\n+return '$cwd/migration-results';",
    }),
    buildPatchedFile({
      filename: 'website/docs/reference/file-locations.md',
      changes: 4,
      patch: '@@ -1,1 +1,1 @@\n+Artifacts now live under migration-results/<timestamp>/ with session-file examples nearby.',
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildContractDocsFindings blocks CLI command surface changes without docs sync', () => {
  const findings = buildContractDocsFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/config/arg_parsers.dart',
      changes: 12,
      patch: "@@ -1,1 +1,1 @@\n+return 'Usage: $publicCommandName settings <action> [options]\\n';",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'command_surface_docs_gap');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildContractDocsFindings blocks settings action changes without docs sync', () => {
  const findings = buildContractDocsFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/core/settings.dart',
      changes: 8,
      patch: "@@ -1,1 +1,1 @@\n+const String settingsActionSetTokenEnv = 'set-token-env';",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'settings_actions_docs_gap');
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

// --- buildRawExceptionFindings ---

test('buildRawExceptionFindings flags generic Exception throw in production Dart', () => {
  const findings = buildRawExceptionFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/core/http.dart',
      patch: '@@ -10,0 +11,1 @@\n+    throw Exception(\'unexpected status\');',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'raw_exception_in_production');
  assert.match(findings[0].message, /project-specific exceptions/);
});

test('buildRawExceptionFindings flags StateError in production Dart', () => {
  const findings = buildRawExceptionFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/engine.dart',
      patch: "@@ -5,0 +6,1 @@\n+    throw StateError('no releases');",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.match(findings[0].message, /MigrationPhaseError/);
});

test('buildRawExceptionFindings ignores generated files', () => {
  const findings = buildRawExceptionFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/models/config.g.dart',
      patch: "@@ -1,0 +1,1 @@\n+    throw Exception('generated');",
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildRawExceptionFindings ignores test files', () => {
  const findings = buildRawExceptionFindings([
    buildPatchedFile({
      filename: 'dart_cli/test/unit/core/http_test.dart',
      patch: "@@ -1,0 +1,1 @@\n+    throw Exception('in test');",
    }),
  ]);

  assert.deepEqual(findings, []);
});

// --- buildSilentCatchFindings ---

test('buildSilentCatchFindings blocks empty catch in Dart production code', () => {
  const findings = buildSilentCatchFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/core/settings.dart',
      patch: '@@ -20,0 +21,1 @@\n+    } catch (e) {}',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'silent_catch_block');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildSilentCatchFindings blocks empty catch in Flutter production code', () => {
  const findings = buildSilentCatchFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/runtime/run/gfrm_desktop_run_controller.dart',
      patch: '@@ -5,0 +6,1 @@\n+    } catch (e) {}',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'silent_catch_block');
});

test('buildSilentCatchFindings ignores catch with body', () => {
  const findings = buildSilentCatchFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/core/settings.dart',
      patch: '@@ -20,0 +21,1 @@\n+    } catch (e) { stderr.writeln(e); }',
    }),
  ]);

  assert.deepEqual(findings, []);
});

// --- buildPrintInProductionFindings ---

test('buildPrintInProductionFindings flags print() in Dart production code', () => {
  const findings = buildPrintInProductionFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/engine.dart',
      patch: "@@ -30,0 +31,1 @@\n+    print('debug: $tag');",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'print_in_production');
  assert.equal(findings[0].severity, 'note');
});

test('buildPrintInProductionFindings flags print() in Flutter production code', () => {
  const findings = buildPrintInProductionFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/app/gfrm_app.dart',
      patch: "@@ -10,0 +11,1 @@\n+    print('app started');",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'print_in_production');
});

test('buildPrintInProductionFindings ignores commented-out print', () => {
  const findings = buildPrintInProductionFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/core/http.dart',
      patch: "@@ -5,0 +6,1 @@\n+    // print('debug');",
    }),
  ]);

  assert.deepEqual(findings, []);
});

// --- buildFlutterTestFindings ---

test('buildFlutterTestFindings blocks new Flutter source without tests', () => {
  const findings = buildFlutterTestFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/features/dashboard/presentation/dashboard_page.dart',
      status: 'added',
      changes: 50,
      patch: '@@ -0,0 +1,3 @@\n+class DashboardPage extends StatelessWidget {}\n+\n+Widget build(context) => Container();',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'missing_flutter_tests_for_new_source');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildFlutterTestFindings stays quiet when Flutter tests changed', () => {
  const findings = buildFlutterTestFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/features/dashboard/presentation/dashboard_page.dart',
      status: 'added',
      changes: 50,
      patch: '@@ -0,0 +1,3 @@\n+class DashboardPage extends StatelessWidget {}',
    }),
    buildPatchedFile({
      filename: 'gui/test/widget/dashboard_test.dart',
      status: 'added',
      changes: 20,
      patch: '@@ -0,0 +1,1 @@\n+void main() {}',
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildFlutterTestFindings emits note for large modified Flutter source', () => {
  const findings = buildFlutterTestFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/runtime/run/gfrm_desktop_run_controller.dart',
      status: 'modified',
      changes: 150,
      patch: '@@ -10,3 +10,3 @@\n+refactored();',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'consider_flutter_test_updates');
  assert.equal(findings[0].severity, 'note');
});

test('buildFlutterTestFindings ignores generated files', () => {
  const findings = buildFlutterTestFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/runtime/run/desktop_run_controller_provider.g.dart',
      status: 'added',
      changes: 80,
      patch: '@@ -0,0 +1,3 @@\n+// GENERATED CODE',
    }),
  ]);

  assert.deepEqual(findings, []);
});

// --- buildFlutterTargetedCoverageFindings ---

test('buildFlutterTargetedCoverageFindings flags controller change without test', () => {
  const findings = buildFlutterTargetedCoverageFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/runtime/run/gfrm_desktop_run_controller.dart',
      changes: 10,
      patch: '@@ -5,0 +6,1 @@\n+  final DesktopRunSnapshot snapshot;',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'flutter_controller_test_gap');
  assert.equal(findings[0].severity, 'note');
});

test('buildFlutterTargetedCoverageFindings stays quiet when controller test changed', () => {
  const findings = buildFlutterTargetedCoverageFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/runtime/run/gfrm_desktop_run_controller.dart',
      changes: 10,
      patch: '@@ -5,0 +6,1 @@\n+  final DesktopRunSnapshot snapshot;',
    }),
    buildPatchedFile({
      filename: 'gui/test/unit/runtime/run/gfrm_desktop_run_controller_test.dart',
      changes: 5,
      patch: '@@ -1,0 +1,1 @@\n+test added',
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildFlutterTargetedCoverageFindings stays quiet when app theme token test changed', () => {
  const findings = buildFlutterTargetedCoverageFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/theme/gfrm_colors.dart',
      changes: 10,
      patch: "@@ -1,1 +1,1 @@\n+part of 'gfrm_app_theme.dart';",
    }),
    buildPatchedFile({
      filename: 'gui/test/unit/theme/gfrm_app_theme_test.dart',
      changes: 12,
      patch: '@@ -0,0 +1,1 @@\n+test added',
    }),
  ]);

  assert.deepEqual(findings, []);
});

// --- buildMultiClassFindings ---

test('buildMultiClassFindings blocks multiple classes in one Dart file', () => {
  const findings = buildMultiClassFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/models/config.dart',
      patch: '@@ -0,0 +1,4 @@\n+class ConfigA {\n+}\n+class ConfigB {\n+}',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'multi_class_single_file');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildMultiClassFindings allows single class', () => {
  const findings = buildMultiClassFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/models/config.dart',
      patch: '@@ -0,0 +1,2 @@\n+class Config {\n+}',
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildMultiClassFindings ignores generated files', () => {
  const findings = buildMultiClassFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/runtime/run/provider.g.dart',
      patch: '@@ -0,0 +1,4 @@\n+class GeneratedA {}\n+class GeneratedB {}',
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildMultiClassFindings blocks multiple classes in Flutter files', () => {
  const findings = buildMultiClassFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/app/widgets.dart',
      patch: '@@ -0,0 +1,4 @@\n+class WidgetA extends StatelessWidget {\n+}\n+class WidgetB extends StatelessWidget {\n+}',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'multi_class_single_file');
});

// --- buildLogicInBuildFindings ---

test('buildLogicInBuildFindings blocks await inside build method', () => {
  const findings = buildLogicInBuildFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/features/dashboard/presentation/dashboard_page.dart',
      patch: '@@ -0,0 +1,5 @@\n+  Widget build(BuildContext context) {\n+    final data = await fetchData();\n+    return Text(data);\n+  }',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'logic_in_build_method');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildLogicInBuildFindings blocks HTTP call inside build', () => {
  const findings = buildLogicInBuildFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/features/settings/presentation/settings_page.dart',
      patch: '@@ -0,0 +1,5 @@\n+  Widget build(BuildContext context) {\n+    http.get(Uri.parse(url));\n+    return Container();\n+  }',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'logic_in_build_method');
});

test('buildLogicInBuildFindings ignores non-Flutter files', () => {
  const findings = buildLogicInBuildFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/core/http.dart',
      patch: '@@ -0,0 +1,5 @@\n+  Widget build(BuildContext context) {\n+    await fetch();\n+    return x;\n+  }',
    }),
  ]);

  assert.deepEqual(findings, []);
});

// --- buildGodClassFindings ---

test('buildGodClassFindings blocks new file over 500 lines', () => {
  const findings = buildGodClassFindings([
    {
      filename: 'dart_cli/lib/src/migrations/mega_engine.dart',
      status: 'added',
      additions: 520,
      changes: 520,
      patch: '@@ -0,0 +1,1 @@\n+class MegaEngine {}',
    },
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'god_class_new_file');
  assert.equal(findings[0].severity, 'blocking');
  assert.match(findings[0].message, /520/);
});

test('buildGodClassFindings allows new file under 500 lines', () => {
  const findings = buildGodClassFindings([
    {
      filename: 'dart_cli/lib/src/models/small.dart',
      status: 'added',
      additions: 80,
      changes: 80,
      patch: '@@ -0,0 +1,1 @@\n+class Small {}',
    },
  ]);

  assert.deepEqual(findings, []);
});

test('buildGodClassFindings ignores modified files', () => {
  const findings = buildGodClassFindings([
    {
      filename: 'dart_cli/lib/src/migrations/engine.dart',
      status: 'modified',
      additions: 600,
      changes: 600,
      patch: '@@ -1,0 +1,1 @@\n+big change',
    },
  ]);

  assert.deepEqual(findings, []);
});

// --- buildLongMethodFindings ---

test('buildLongMethodFindings flags method exceeding 120 added lines', () => {
  const bodyLines = Array.from({ length: 125 }, (_, i) => `+    final x${i} = ${i};`).join('\n');
  const patch = `@@ -0,0 +1,128 @@\n+  Future<void> processAll(List<String> items) {\n${bodyLines}\n+    return;\n+  }`;
  const findings = buildLongMethodFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/engine.dart',
      patch,
    }),
  ]);

  assert.ok(findings.length >= 1, `Expected findings but got ${findings.length}`);
  assert.equal(findings[0].rule, 'long_method');
  assert.equal(findings[0].severity, 'note');
});

test('buildLongMethodFindings stays quiet for short methods', () => {
  const lines = Array.from({ length: 10 }, (_, i) => `+  statement${i};`).join('\n');
  const findings = buildLongMethodFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/core/settings.dart',
      patch: `@@ -0,0 +1,12 @@\n+void shortMethod() {\n${lines}\n+}`,
    }),
  ]);

  assert.deepEqual(findings, []);
});

// --- buildSetStateFindings ---

test('buildSetStateFindings blocks setState in Flutter production code', () => {
  const findings = buildSetStateFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/features/dashboard/presentation/dashboard_page.dart',
      patch: '@@ -10,0 +11,1 @@\n+    setState(() { _counter++; });',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'set_state_in_riverpod_project');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildSetStateFindings ignores commented setState', () => {
  const findings = buildSetStateFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/app/gfrm_app.dart',
      patch: '@@ -10,0 +11,1 @@\n+    // setState(() { old pattern });',
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildSetStateFindings ignores non-Flutter files', () => {
  const findings = buildSetStateFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/core/settings.dart',
      patch: '@@ -10,0 +11,1 @@\n+    setState(() {});',
    }),
  ]);

  assert.deepEqual(findings, []);
});

// --- buildDirectDependencyFindings ---

test('buildDirectDependencyFindings blocks engine importing concrete provider', () => {
  const findings = buildDirectDependencyFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/engine.dart',
      patch: "@@ -1,0 +2,1 @@\n+import '../providers/github.dart';",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'engine_imports_provider_directly');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildDirectDependencyFindings blocks direct HTTP in engine', () => {
  const findings = buildDirectDependencyFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/tag_phase.dart',
      patch: '@@ -10,0 +11,1 @@\n+    final response = await requestJson(url);',
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'engine_makes_http_calls');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildDirectDependencyFindings ignores provider imports outside engine', () => {
  const findings = buildDirectDependencyFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/application/run_service.dart',
      patch: "@@ -1,0 +2,1 @@\n+import '../providers/github.dart';",
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildDirectDependencyFindings ignores comments', () => {
  const findings = buildDirectDependencyFindings([
    buildPatchedFile({
      filename: 'dart_cli/lib/src/migrations/engine.dart',
      patch: "@@ -1,0 +2,1 @@\n+// import '../providers/github.dart';",
    }),
  ]);

  assert.deepEqual(findings, []);
});

// --- buildGuiBoundaryFindings ---

test('buildGuiBoundaryFindings blocks GUI importing cli.dart', () => {
  const findings = buildGuiBoundaryFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/runtime/run/gfrm_desktop_run_controller.dart',
      patch: "@@ -1,0 +2,1 @@\n+import 'package:gfrm_dart/src/cli.dart';",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'gui_imports_cli_internals');
  assert.equal(findings[0].severity, 'blocking');
});

test('buildGuiBoundaryFindings blocks GUI importing arg_parsers', () => {
  const findings = buildGuiBoundaryFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/app/gfrm_app.dart',
      patch: "@@ -1,0 +2,1 @@\n+import 'package:gfrm_dart/src/config/arg_parsers.dart';",
    }),
  ]);

  assert.equal(findings.length, 1);
  assert.equal(findings[0].rule, 'gui_imports_cli_internals');
});

test('buildGuiBoundaryFindings allows GUI importing application layer', () => {
  const findings = buildGuiBoundaryFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/runtime/run/gfrm_desktop_run_controller.dart',
      patch: "@@ -1,0 +2,1 @@\n+import 'package:gfrm_dart/src/application/run_service.dart';",
    }),
  ]);

  assert.deepEqual(findings, []);
});

test('buildGuiBoundaryFindings ignores comments', () => {
  const findings = buildGuiBoundaryFindings([
    buildPatchedFile({
      filename: 'gui/lib/src/app/gfrm_app.dart',
      patch: "@@ -1,0 +2,1 @@\n+// import 'package:gfrm_dart/src/cli.dart';",
    }),
  ]);

  assert.deepEqual(findings, []);
});
