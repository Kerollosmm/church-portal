import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { buildFileMap, buildExcludeRegexes } from './publish_hosting_file.js';

test('buildFileMap in single-file mode', () => {
  const map = buildFileMap({
    localFile: 'out/today.json',
    hostingPath: '/data/today.json',
  });
  assert.deepEqual(map, {
    '/data/today.json': 'out/today.json',
  });
});

test('buildFileMap in multi-file mode with dir and extra file', () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'readings-test-'));
  fs.writeFileSync(path.join(tmpDir, '2026-11-07.json'), '{}');
  fs.writeFileSync(path.join(tmpDir, '2026-11-08.json'), '{}');

  const map = buildFileMap({
    dir: tmpDir,
    prefix: '/data/readings/',
    extraFiles: [{ local: 'out/today.json', remote: '/data/today.json' }],
  });

  assert.equal(Object.keys(map).length, 3);
  assert.equal(map['/data/today.json'], 'out/today.json');
  assert.equal(map['/data/readings/2026-11-07.json'], path.join(tmpDir, '2026-11-07.json'));
  assert.equal(map['/data/readings/2026-11-08.json'], path.join(tmpDir, '2026-11-08.json'));

  fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('buildExcludeRegexes produces single-file regex', () => {
  const regexes = buildExcludeRegexes({ hostingPath: '/data/today.json' });
  assert.deepEqual(regexes, ['^/data/today\\.json$']);
});

test('buildExcludeRegexes in multi-file mode produces readings and today regexes', () => {
  const regexes = buildExcludeRegexes({ dir: 'some/dir' });
  assert.deepEqual(regexes, ['^/data/readings/.*[.]json$', '^/data/today[.]json$']);
});

test('buildExcludeRegexes supports custom excludes', () => {
  const regexes = buildExcludeRegexes({
    dir: 'some/dir',
    customExcludes: ['^/app/android/.*$'],
  });
  assert.deepEqual(regexes, ['^/app/android/.*$']);
});
