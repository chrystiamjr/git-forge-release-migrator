#!/usr/bin/env node

const { spawnSync } = require('node:child_process');

function canUseFvm() {
  const probe = spawnSync('fvm', ['dart', '--version'], { stdio: 'ignore' });
  return probe.status === 0;
}

function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error('Usage: node scripts/run-dart.js <dart-args...>');
    process.exit(1);
  }

  const useFvm = canUseFvm();
  const command = useFvm ? 'fvm' : 'dart';
  const commandArgs = useFvm ? ['dart', ...args] : args;
  const result = spawnSync(command, commandArgs, { stdio: 'inherit' });

  if (typeof result.status === 'number') {
    process.exit(result.status);
  }

  process.exit(1);
}

main();
