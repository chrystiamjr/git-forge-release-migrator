import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { prepareSnapshot, boundedProcess } from './review-runner.mjs';

export const EFFORTLESS_REVISION = 'e553b18e9f5e8ce3533f3ce9c666e7e8bc9234f9';
export const ROUTING_ARMS = ['current', 'effortless-effort', 'effortless-model'];

// This is an experiment adapter only. Production publication never loads third-party hooks.
export async function validateEffortlessPlugin(plugin, options, run = boundedProcess) {
  const result = await run('claude', ['plugin', 'validate', plugin], options);
  if (result.exitCode !== 0) throw new Error('Pinned Effortless plugin fails Claude Code static validation; retain current routing');
}

export function effortlessConfiguration(arm, download = prepareSnapshot, validate = validateEffortlessPlugin) {
  if (!ROUTING_ARMS.slice(1).includes(arm)) throw new Error('Unknown Effortless experiment arm');
  return async ({ root, args, env, signal }) => {
    const plugin = await download({ repository: 'HeyCubit/effortless', head: EFFORTLESS_REVISION,
      root: join(root, 'plugin'), signal });
    const manifest = JSON.parse(await readFile(join(plugin, '.claude-plugin/plugin.json'), 'utf8'));
    if (manifest.name !== 'effortless' || manifest.version !== '1.71.0') throw new Error('Unexpected plugin manifest');
    await validate(plugin, { cwd: root, env, signal });
    // Safe mode intentionally disables all plugin code. This isolated arm loads just the pinned plugin.
    args.splice(args.indexOf('--safe-mode'), 1);
    const options = { judge: 'haiku', modelAuto: arm === 'effortless-model' ? 'on' : 'off',
      helpers: 'off', compactWith: 'session', layout: 'minimal' };
    args.push('--plugin-dir', plugin, '--settings', JSON.stringify({
      pluginConfigs: { 'effortless@inline': { options } },
    }));
    env.CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = '1';
    env.EFFORTLESS_LOG = join(root, 'effortless-proof.log');
    return { collect: async () => parseEffortlessProof(await readFile(env.EFFORTLESS_LOG, 'utf8')) };
  };
}

export function parseEffortlessProof(proof) {
  const suggestions = [...proof.matchAll(/judged by (\w+) in (\d+) ms: ([\w.-]+)\/(low|medium|high|xhigh|max)/g)]
    .map((match) => ({ judge: match[1], duration_ms: Number(match[2]), model: match[3], effort: match[4] }));
  const applied = [...proof.matchAll(/request (\d+) \(([^)]+)\): effort \S+ -> (\w+)|request (\d+): (\S+) -> (\S+) at (\w+)/g)]
    .map((match) => ({ request: Number(match[1] ?? match[4]), model: match[2] ?? match[6], effort: match[3] ?? match[7] }));
  if (!suggestions.length || !applied.length) throw new Error('Plugin has no judge/applied-setting evidence');
  if (suggestions.some((item) => item.judge !== 'haiku')) throw new Error('Non-subscription judge observed');
  return { plugin_revision: EFFORTLESS_REVISION, suggested_settings: suggestions, applied_settings: applied,
    // The plugin proof log does not expose judge token usage. Never mislabel main-loop usage as a total.
    judge_usage: null, usage_complete: false };
}

export function buildRiskSummary(files) {
  const areas = [...new Set(files.map((file) => file.filename.split('/').slice(0, 3).join('/')))];
  const risk = files.filter((file) => /auth|token|http|provider|migration|review|workflow|session|release/i.test(file.filename));
  const names = files.map((file) => file.filename);
  const prefix = `PR review; files=${files.length}; changed lines=${files.reduce((n, f) => n + (f.additions || 0) + (f.deletions || 0), 0)}; `
    + `risk-sensitive files=${risk.length}. Areas: ${areas.slice(0, 8).join(', ')}. `
    + `Full patches and source follow; this routing summary is incomplete. Paths: `;
  return `${prefix}${names.join(', ')}`.slice(0, 1800) + '\n';
}
