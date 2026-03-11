#!/usr/bin/env node
/**
 * check-translations.js
 *
 * Validates that PT-BR translation files are complete and up to date.
 * Exits with code 1 if any issues are found.
 *
 * Checks:
 *  1. code.json — all homepage.* and downloadSection.* keys exist and are non-empty
 *  2. current.json — all sidebar category keys exist and are non-empty
 *  3. navbar.json / footer.json — all message values are non-empty
 */

import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const PT_BR = resolve(ROOT, 'website/i18n/pt-BR');

let errors = 0;

function fail(msg) {
  console.error(`  ✗ ${msg}`);
  errors++;
}

function pass(msg) {
  console.log(`  ✓ ${msg}`);
}

function loadJson(filePath) {
  if (!existsSync(filePath)) {
    fail(`Missing file: ${filePath.replace(ROOT + '/', '')}`);
    return null;
  }
  try {
    return JSON.parse(readFileSync(filePath, 'utf8'));
  } catch {
    fail(`Invalid JSON: ${filePath.replace(ROOT + '/', '')}`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// 1. code.json — custom React page/component translations
// ---------------------------------------------------------------------------
console.log('\n[1/3] Checking code.json …');

const codeJson = loadJson(resolve(PT_BR, 'code.json'));

if (codeJson) {
  const REQUIRED_PREFIXES = ['homepage.', 'downloadSection.'];

  // These values are intentionally the same in EN and PT-BR
  const ALLOWED_SAME = new Set([
    'homepage.cta.download',
    'homepage.download.title',
    'downloadSection.downloadButton',
  ]);

  // English defaults embedded in source (used to detect untranslated strings)
  const EN_DEFAULTS = {
    'homepage.kicker': 'Open Source CLI',
    'homepage.hero.title': 'Move releases across Git forges ',
    'homepage.hero.titleAccent': 'without redoing work',
    'homepage.cta.getStarted': 'Get Started',
    'homepage.feature.crossForge.title': 'Cross-forge migrations',
    'homepage.feature.crossForge.description':
      'Migrate between GitHub, GitLab, and Bitbucket Cloud in any direction. One command covers tags, releases, notes, and binary assets.',
    'homepage.feature.resilient.title': 'Resilient by design',
    'homepage.feature.resilient.description':
      'Checkpoint state is written to disk on every step. Interrupted runs resume exactly where they left off with gfrm resume.',
    'homepage.feature.zeroDeps.title': 'Zero runtime dependencies',
    'homepage.feature.zeroDeps.description':
      'Ships as a single compiled binary. No Dart, Node, FVM, or Yarn required on the target machine.',
    'homepage.download.subtitle': 'Pre-compiled binaries for all platforms. No runtime required.',
    'homepage.quickStart.title': 'Quick start',
    'homepage.quickStart.subtitle': 'Download, extract, and run your first migration in minutes.',
    'homepage.readNext.installAndVerify': 'Install and Verify →',
    'homepage.readNext.firstMigration': 'First Migration →',
    'homepage.readNext.fullDocs': 'Full Documentation →',
    'downloadSection.error.message': 'Could not load release information.',
    'downloadSection.error.fallbackLink': 'View all releases on GitHub →',
    'downloadSection.releaseNotes': 'Release notes →',
    'downloadSection.detectedBadge': 'Your platform',
    'downloadSection.unavailable': 'Unavailable',
    'downloadSection.checksumHint': 'Verify your download with SHA256',
  };

  for (const [key, enDefault] of Object.entries(EN_DEFAULTS)) {
    const entry = codeJson[key];
    if (!entry) {
      fail(`Missing key in code.json: "${key}"`);
      continue;
    }
    const msg = entry.message?.trim();
    if (!msg) {
      fail(`Empty translation in code.json: "${key}"`);
      continue;
    }
    if (!ALLOWED_SAME.has(key) && msg === enDefault) {
      fail(`Untranslated (still English) in code.json: "${key}"`);
      continue;
    }
    pass(`code.json["${key}"]`);
  }

  // Check no required-prefix key is empty
  for (const [key, entry] of Object.entries(codeJson)) {
    const isCustom = REQUIRED_PREFIXES.some((p) => key.startsWith(p));
    if (isCustom && !entry.message?.trim()) {
      fail(`Empty message in code.json: "${key}"`);
    }
  }
}

// ---------------------------------------------------------------------------
// 2. current.json — sidebar category translations
// ---------------------------------------------------------------------------
console.log('\n[2/3] Checking current.json …');

const currentJson = loadJson(
  resolve(PT_BR, 'docusaurus-plugin-content-docs/current.json'),
);

if (currentJson) {
  const REQUIRED_CATEGORIES = [
    'sidebar.docs.category.Start Here',
    'sidebar.docs.category.Configuration',
    'sidebar.docs.category.Commands',
    'sidebar.docs.category.Guides',
    'sidebar.docs.category.Reference',
    'sidebar.docs.category.Project',
  ];

  for (const key of REQUIRED_CATEGORIES) {
    const entry = currentJson[key];
    if (!entry) {
      fail(`Missing key in current.json: "${key}"`);
      continue;
    }
    if (!entry.message?.trim()) {
      fail(`Empty translation in current.json: "${key}"`);
      continue;
    }
    pass(`current.json["${key}"]`);
  }
}

// ---------------------------------------------------------------------------
// 3. navbar.json + footer.json — theme labels
// ---------------------------------------------------------------------------
console.log('\n[3/3] Checking navbar.json and footer.json …');

// Keys that are intentionally empty (e.g. navbar title hidden in favour of logo)
const ALLOWED_EMPTY = new Set(['navbar.json:title']);

for (const file of ['navbar.json', 'footer.json']) {
  const data = loadJson(resolve(PT_BR, 'docusaurus-theme-classic', file));
  if (!data) continue;

  for (const [key, entry] of Object.entries(data)) {
    if (!entry.message?.trim()) {
      if (ALLOWED_EMPTY.has(`${file}:${key}`)) {
        pass(`${file}["${key}"] (intentionally empty)`);
      } else {
        fail(`Empty translation in ${file}: "${key}"`);
      }
    } else {
      pass(`${file}["${key}"]`);
    }
  }
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
console.log('');
if (errors > 0) {
  console.error(
    `\n❌  PT-BR translation check failed with ${errors} error(s).\n` +
      `   Fix the issues above or update website/i18n/pt-BR/ files before committing.\n`,
  );
  process.exit(1);
} else {
  console.log('✅  All PT-BR translations are complete.\n');
}
