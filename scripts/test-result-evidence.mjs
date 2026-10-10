import { relative } from 'node:path';

export function normalizeTestPath(path, root) {
  try { if (path.startsWith('file:')) path = new URL(path).pathname; } catch { return ''; }
  return (path.startsWith(root + '/') ? relative(root, path) : path).replaceAll('\\', '/');
}

export function parseTestEvidence(output, suite, root) {
  const starts = new Map();
  const results = [];
  for (const line of output.split('\n')) {
    let event;
    try { event = JSON.parse(line); } catch { continue; }
    if (event.type === 'testStart') starts.set(event.test.id, event.test);
    if (event.type === 'testDone') {
      const test = starts.get(event.testID);
      if (!test?.url || event.hidden) continue;
      results.push({ suite, file: normalizeTestPath(test.url || '', root), name: test.name,
        status: event.skipped || test.metadata?.skip ? 'skipped' : event.result === 'success' ? 'passed' : 'failed' });
    }
    if (event.type === 'test:pass' || event.type === 'test:fail') {
      // Suite containers do not prove that a named test ran.
      if (event.data.details?.type === 'suite') continue;
      results.push({ suite, file: normalizeTestPath(event.data.file || '', root), name: event.data.name,
        status: event.data.skip || event.data.todo ? 'skipped' : event.type === 'test:pass' ? 'passed' : 'failed' });
    }
  }
  if (suite === 'website') {
    // Vitest JSON can be preceded by Yarn's startup output.
    const start = output.search(/\{\s*"numTotalTestSuites"\s*:/);
    try {
      const report = JSON.parse(output.slice(start));
      for (const file of report.testResults || []) for (const test of file.assertionResults || []) {
        results.push({ suite, file: normalizeTestPath(file.name, root), name: test.fullName,
          status: test.status === 'passed' ? 'passed' : test.status === 'failed' ? 'failed' : 'skipped' });
      }
    } catch { /* Unavailable named evidence leaves scenarios pending. */ }
  }
  return results;
}
