#!/usr/bin/env node
/**
 * validate-commit-msg.mjs
 *
 * Validates a single commit message against the Conventional Commits spec:
 *   type(scope): short description
 *   [blank line]
 *   [optional body]
 *
 * Usage:
 *   node scripts/validate-commit-msg.mjs --file <path>   # commit-msg hook
 *   node scripts/validate-commit-msg.mjs "<message>"     # ad-hoc / pre-push
 */

import { readFileSync } from 'fs';

const TYPES = [
  'feat',
  'fix',
  'chore',
  'docs',
  'refactor',
  'test',
  'ci',
  'style',
  'perf',
  'build',
  'revert',
];

const SUBJECT_MAX_LENGTH = 72;

// type(required-scope)optional-!: description (1–72 chars)
const SUBJECT_RE = new RegExp(
  `^(${TYPES.join('|')})(\\([^)]+\\))!?: .{1,${SUBJECT_MAX_LENGTH}}$`,
);

// Commit subjects to skip validation (auto-generated / tooling)
const SKIP_PREFIXES = [
  'Merge ',       // git merge commits
  'Revert "',     // git revert commits
  "Merge branch", // local branch merges
];

function validate(raw) {
  const lines = raw.trim().split('\n');
  const subject = lines[0].trim();

  if (SKIP_PREFIXES.some((p) => subject.startsWith(p))) {
    return { valid: true, skipped: true };
  }

  if (!SUBJECT_RE.test(subject)) {
    const lines_ = [
      `  Subject : "${subject}"`,
      '',
      `  Expected : type(scope): short description`,
      `  Scope    : required`,
      `  Max len  : ${SUBJECT_MAX_LENGTH} characters`,
      `  Types    : ${TYPES.join(', ')}`,
      '',
      '  Examples :',
      '    feat(cli): add resume command',
      '    fix: handle empty release list',
      '    chore(deps): update dart dependencies',
      '    docs: improve quick start guide',
      '    ci(release): add macOS arm64 artifact',
    ];
    return { valid: false, error: lines_.join('\n') };
  }

  // Body (if present) must be separated from subject by a blank line
  if (lines.length > 1 && lines[1].trim() !== '') {
    return {
      valid: false,
      error: '  Commit body must be separated from the subject by a blank line.',
    };
  }

  return { valid: true };
}

// ── Entry point ─────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
let message;

if (args[0] === '--file' && args[1]) {
  message = readFileSync(args[1], 'utf8');
} else if (args.length >= 1) {
  message = args.join(' ');
} else {
  console.error('Usage: node scripts/validate-commit-msg.mjs --file <path>');
  console.error('       node scripts/validate-commit-msg.mjs "<message>"');
  process.exit(1);
}

const result = validate(message);

if (!result.valid) {
  console.error('\n❌  Invalid commit message:\n');
  console.error(result.error);
  console.error('');
  process.exit(1);
}
