#!/usr/bin/env node

const { spawnSync } = require('node:child_process');

function sdkEnvironment() {
  const env = { ...process.env };
  for (const name of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR']) delete env[name];
  return env;
}

function canUseFvm() {
  const probe = spawnSync('fvm', ['dart', '--version'], { stdio: 'ignore', env: sdkEnvironment() });
  return probe.status === 0;
}

function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error('Usage: node scripts/run-dart.js <dart-args...>');
    process.exit(1);
  }

  const sdk = args[0] === '--flutter' ? (args.shift(), 'flutter') : 'dart';
  const useFvm = canUseFvm();
  const command = useFvm ? 'fvm' : sdk;
  const commandArgs = useFvm ? [sdk, ...args] : args;
  const result = spawnSync(command, commandArgs, { stdio: 'inherit', env: sdkEnvironment() });

  if (typeof result.status === 'number') {
    process.exit(result.status);
  }

  process.exit(1);
}

if (require.main === module) main();
module.exports = { sdkEnvironment };
