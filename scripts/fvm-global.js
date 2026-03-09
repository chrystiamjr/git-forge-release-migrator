const { execSync } = require('child_process');
const { flutter } = JSON.parse(require('fs').readFileSync('.fvmrc', 'utf8'));
execSync(`fvm global ${flutter}`, { stdio: 'inherit' });