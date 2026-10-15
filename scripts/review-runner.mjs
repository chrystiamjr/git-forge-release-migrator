import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REVIEW_CLI_VERSION = '2.1.296';
export const VERIFICATION_TIMEOUT_MS = 180_000;
const OUTPUT_LIMIT = 64 * 1024 * 1024;

// In particular, never inherit API billing, GitHub credentials, user hooks or NODE_OPTIONS.
export function subscriptionEnv(env, root) {
  if (!env.CLAUDE_CODE_OAUTH_TOKEN) throw new Error('Subscription OAuth token is required');
  return {
    PATH: env.PATH, HOME: root, TMPDIR: root, CLAUDE_CONFIG_DIR: join(root, 'config'),
    CLAUDE_CODE_OAUTH_TOKEN: env.CLAUDE_CODE_OAUTH_TOKEN,
    CLAUDE_CODE_DISABLE_AUTO_MEMORY: '1', DISABLE_AUTOUPDATER: '1',
  };
}

export function boundedProcess(command, args, { cwd, env, input, signal } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, env, signal, killSignal: 'SIGKILL', stdio: ['pipe', 'pipe', 'pipe'] });
    const stdout = [], stderr = [];
    let size = 0;
    let overflow = false;
    const capture = (list) => (chunk) => {
      size += chunk.length;
      if (size > OUTPUT_LIMIT) { overflow = true; child.kill('SIGKILL'); }
      else list.push(chunk);
    };
    child.stdout.on('data', capture(stdout));
    child.stderr.on('data', capture(stderr));
    child.stdin.on('error', () => {});
    child.on('error', reject);
    child.on('close', (exitCode) => overflow ? reject(new Error('Review output limit exceeded')) : resolve({
      exitCode, stdout: Buffer.concat(stdout), stderr: Buffer.concat(stderr),
    }));
    child.stdin.end(input);
  });
}

export async function prepareSnapshot({ repository, head, root, signal, run = boundedProcess }) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository) || !/^[a-f0-9]{40}$/.test(head)) {
    throw new Error('Snapshot requires repository and full immutable head SHA');
  }
  await mkdir(root, { recursive: true });
  const archive = join(root, 'snapshot.tar.gz');
  const result = await run('gh', ['api', `/repos/${repository}/tarball/${head}`], { signal });
  if (result.exitCode !== 0) throw new Error('Cannot download revision snapshot');
  await writeFile(archive, result.stdout);
  const destination = join(root, 'work', 'repo');
  const extracted = await run('python3', [fileURLToPath(new URL('./review-snapshot.py', import.meta.url)), archive, destination], { signal });
  await rm(archive, { force: true });
  if (extracted.exitCode !== 0) throw new Error('Cannot extract data-only snapshot');
  return destination;
}

export function readOnlyArgs({ model = 'sonnet', effort = 'medium', system, schema }) {
  return ['-p', '--restricted', '--safe-mode', '--tools', 'Read,Grep,Glob', '--allowedTools', 'Read,Grep,Glob',
    '--permission-mode', 'dontAsk', '--strict-mcp-config', '--disable-slash-commands', '--no-session-persistence',
    '--model', model, '--effort', effort, '--output-format', 'json', '--system-prompt', system,
    '--json-schema', JSON.stringify(schema)];
}

export async function isolatedReview({ repository, head, system, schema, input, env = process.env,
  assertCurrent = async () => {}, run = boundedProcess, snapshot = prepareSnapshot,
  timeoutMs = VERIFICATION_TIMEOUT_MS, configure, validate = async () => {}, model = 'sonnet', effort = 'medium',
  fileTools = true }) {
  const root = await mkdtemp(join(tmpdir(), 'gfrm-verifier-'));
  const started = Date.now();
  const controller = new AbortController();
  const deadline = setTimeout(() => controller.abort(), timeoutMs);
  const guard = async () => {
    controller.signal.throwIfAborted();
    let cancel;
    const aborted = new Promise((_, reject) => {
      cancel = () => reject(new Error('Verification deadline exceeded'));
      controller.signal.addEventListener('abort', cancel, { once: true });
    });
    try { await Promise.race([assertCurrent(), aborted]); }
    finally { controller.signal.removeEventListener('abort', cancel); }
  };
  let stopped;
  let checking = false;
  const watch = setInterval(async () => {
    if (checking) return;
    checking = true;
    try { await assertCurrent(); } catch (error) { stopped = error; controller.abort(); }
    finally { checking = false; }
  }, 5000);
  try {
    const childEnv = subscriptionEnv(env, root);
    await guard();
    const version = await run('claude', ['--version'], { env: childEnv, cwd: root, signal: controller.signal });
    if (version.exitCode !== 0 || !String(version.stdout).startsWith(`${REVIEW_CLI_VERSION} `)) {
      throw new Error(`Review requires Claude Code ${REVIEW_CLI_VERSION}`);
    }
    await mkdir(join(root, 'config'), { recursive: true });
    await snapshot({ repository, head, root, signal: controller.signal });
    await guard();
    const args = readOnlyArgs({ system, schema, model, effort });
    if (!fileTools) {
      args[args.indexOf('--tools') + 1] = '';
      args.splice(args.indexOf('--allowedTools'), 2);
    }
    const extra = configure ? await configure({ root, args, env: childEnv, signal: controller.signal }) : {};
    const result = await run('claude', args, {
      cwd: join(root, 'work'), env: childEnv, input, signal: controller.signal,
    });
    if (stopped) throw stopped;
    await guard();
    if (result.exitCode !== 0) throw new Error('Isolated review process failed');
    const payload = JSON.parse(String(result.stdout));
    if (payload.is_error || payload.subtype !== 'success' || !payload.structured_output) throw new Error('Incomplete structured review');
    await validate(payload.structured_output, { root });
    const collected = extra.collect ? await extra.collect() : {};
    controller.signal.throwIfAborted();
    return { output: payload.structured_output, usage: payload.usage, model_usage: payload.modelUsage,
      duration_seconds: (Date.now() - started) / 1000,
      requested_settings: { model, effort },
      cost_usd: payload.total_cost_usd ?? null, ...collected };
  } catch (error) {
    if (stopped) throw stopped;
    if (controller.signal.aborted) throw new Error('Verification deadline exceeded');
    throw error;
  } finally {
    clearTimeout(deadline);
    clearInterval(watch);
    await rm(root, { recursive: true, force: true });
  }
}
