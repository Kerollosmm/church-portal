import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { checkWebBundle, DEFAULT_DEFERRED_MODULES, DEFAULT_REQUIRED_FONTS } from './check_web_bundle.mjs';

function createSyntheticBuild(t) {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bundle-test-'));
  if (t && typeof t.after === 'function') {
    t.after(() => {
      try {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      } catch {
        // ignore cleanup error
      }
    });
  }

  // 1. main.dart.js
  fs.writeFileSync(path.join(tmpDir, 'main.dart.js'), 'console.log("synthetic main bundle");');

  // 2. main.dart.js.map (pure, no deferred modules)
  fs.writeFileSync(
    path.join(tmpDir, 'main.dart.js.map'),
    JSON.stringify({
      version: 3,
      sources: ['../../../lib/main.dart', '../../../lib/ui/pages/home_page.dart'],
      mappings: 'AAAA',
    })
  );

  // 3. 8 part chunks covering the 8 deferred modules
  for (let i = 1; i <= DEFAULT_DEFERRED_MODULES.length; i++) {
    const pf = `main.dart.js_${i}.part.js`;
    fs.writeFileSync(path.join(tmpDir, pf), `console.log("chunk ${i}");`);
    fs.writeFileSync(
      path.join(tmpDir, `${pf}.map`),
      JSON.stringify({
        version: 3,
        sources: [`../../../lib/${DEFAULT_DEFERRED_MODULES[i - 1]}`],
        mappings: 'BBBB',
      })
    );
  }

  // 4. fonts under assets/assets/fonts/
  const fontDir = path.join(tmpDir, 'assets', 'assets', 'fonts');
  fs.mkdirSync(fontDir, { recursive: true });
  const fontData = Buffer.alloc(25 * 1024, 0x5a); // 25 KB > 20 KB
  for (const font of DEFAULT_REQUIRED_FONTS) {
    fs.writeFileSync(path.join(fontDir, font), fontData);
  }

  return tmpDir;
}

test('checkWebBundle passes for valid synthetic build', (t) => {
  const dir = createSyntheticBuild(t);
  const result = checkWebBundle(dir, {
    maxGzipBytes: 50000,
    minPartCount: 6,
    minFontBytes: 20480,
  });

  assert.equal(result.success, true);
  assert.equal(result.errors.length, 0);
  assert.equal(result.mainBundle.passed, true);
  assert.equal(result.partCountPassed, true);
  assert.equal(result.deferredIsolation.passed, true);
  assert.equal(result.fontIntegrity.passed, true);
});

test('checkWebBundle fails when main.dart.js gzip exceeds budget', (t) => {
  const dir = createSyntheticBuild(t);
  const result = checkWebBundle(dir, {
    maxGzipBytes: 10, // unrealistically low budget
  });

  assert.equal(result.success, false);
  assert.equal(result.mainBundle.passed, false);
  assert.ok(result.errors.some((e) => e.includes('exceeds ceiling')));
});

test('checkWebBundle fails when a deferred module leaks into main.dart.js.map', (t) => {
  const dir = createSyntheticBuild(t);
  const mainMapPath = path.join(dir, 'main.dart.js.map');
  const mainMap = JSON.parse(fs.readFileSync(mainMapPath, 'utf8'));
  mainMap.sources.push('../../../lib/ui/admin/admin_page.dart');
  fs.writeFileSync(mainMapPath, JSON.stringify(mainMap));

  const result = checkWebBundle(dir);

  assert.equal(result.success, false);
  assert.equal(result.deferredIsolation.passed, false);
  assert.equal(result.deferredIsolation.leaks.length, 1);
  assert.equal(result.deferredIsolation.leaks[0].module, 'ui/admin/admin_page.dart');
  assert.ok(result.errors.some((e) => e.includes('LEAKED into main.dart.js.map: ui/admin/admin_page.dart')));
});

test('checkWebBundle fails when deferred part chunk count is below minimum', (t) => {
  const dir = createSyntheticBuild(t);
  // Remove several part files to drop below minPartCount
  fs.unlinkSync(path.join(dir, 'main.dart.js_7.part.js'));
  fs.unlinkSync(path.join(dir, 'main.dart.js_8.part.js'));
  fs.unlinkSync(path.join(dir, 'main.dart.js_6.part.js'));
  fs.unlinkSync(path.join(dir, 'main.dart.js_5.part.js'));

  const result = checkWebBundle(dir, { minPartCount: 6 });

  assert.equal(result.success, false);
  assert.equal(result.partCountPassed, false);
  assert.ok(result.errors.some((e) => e.includes('expected at least 6')));
});

test('checkWebBundle fails when a deferred module is missing from all part chunks', (t) => {
  const dir = createSyntheticBuild(t);
  // Overwrite part map for readings_page so it is nowhere to be found
  const pMapPath = path.join(dir, 'main.dart.js_4.part.js.map');
  fs.writeFileSync(pMapPath, JSON.stringify({ version: 3, sources: [], mappings: '' }));

  const result = checkWebBundle(dir);

  assert.equal(result.success, false);
  assert.equal(result.deferredIsolation.passed, false);
  assert.ok(result.deferredIsolation.missingInParts.includes('ui/pages/readings_page.dart'));
  assert.ok(result.errors.some((e) => e.includes('NOT FOUND in any part chunk sourcemap: ui/pages/readings_page.dart')));
});

test('checkWebBundle fails when main.dart.js.map is missing', (t) => {
  const dir = createSyntheticBuild(t);
  fs.unlinkSync(path.join(dir, 'main.dart.js.map'));

  const result = checkWebBundle(dir);

  assert.equal(result.success, false);
  assert.equal(result.deferredIsolation.passed, false);
  assert.ok(result.errors.some((e) => e.includes('main.dart.js.map not found')));
});

test('checkWebBundle fails when main.dart.js.map is malformed JSON', (t) => {
  const dir = createSyntheticBuild(t);
  fs.writeFileSync(path.join(dir, 'main.dart.js.map'), 'NOT_VALID_JSON{');

  const result = checkWebBundle(dir);

  assert.equal(result.success, false);
  assert.equal(result.deferredIsolation.passed, false);
  assert.ok(result.errors.some((e) => e.includes('Failed to parse main.dart.js.map')));
});

test('checkWebBundle fails when a required font file is missing', (t) => {
  const dir = createSyntheticBuild(t);
  const fontPath = path.join(dir, 'assets', 'assets', 'fonts', 'Lalezar-Regular.ttf');
  fs.unlinkSync(fontPath);

  const result = checkWebBundle(dir);

  assert.equal(result.success, false);
  assert.equal(result.fontIntegrity.passed, false);
  assert.ok(result.errors.some((e) => e.includes('Required font missing: Lalezar-Regular.ttf')));
});

test('checkWebBundle fails when a required font file is truncated below minimum size', (t) => {
  const dir = createSyntheticBuild(t);
  const fontPath = path.join(dir, 'assets', 'assets', 'fonts', 'ArefRuqaa-Bold.ttf');
  fs.writeFileSync(fontPath, Buffer.alloc(1024, 0x00)); // 1 KB < 20 KB

  const result = checkWebBundle(dir);

  assert.equal(result.success, false);
  assert.equal(result.fontIntegrity.passed, false);
  assert.ok(result.errors.some((e) => e.includes('Font file truncated: ArefRuqaa-Bold.ttf')));
});

test('checkWebBundle handles null and non-string entries in sourcemap sources without throwing', (t) => {
  const dir = createSyntheticBuild(t);
  const mainMapPath = path.join(dir, 'main.dart.js.map');
  const mainMap = JSON.parse(fs.readFileSync(mainMapPath, 'utf8'));
  mainMap.sources.push(null, undefined, 12345, { bad: true });
  fs.writeFileSync(mainMapPath, JSON.stringify(mainMap));

  const pMapPath = path.join(dir, 'main.dart.js_1.part.js.map');
  const pMap = JSON.parse(fs.readFileSync(pMapPath, 'utf8'));
  pMap.sources.unshift(null, 42);
  fs.writeFileSync(pMapPath, JSON.stringify(pMap));

  const result = checkWebBundle(dir);
  assert.equal(result.success, true);
  assert.equal(result.deferredIsolation.passed, true);
});
