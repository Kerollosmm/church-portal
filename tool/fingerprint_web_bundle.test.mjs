import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import {
  checkWebBundle,
  DEFAULT_DEFERRED_MODULES,
  DEFAULT_REQUIRED_FONTS,
} from './check_web_bundle.mjs';

const SCRIPT = path.resolve('tool', 'fingerprint_web_bundle.py');

function createFixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fp-web-bundle-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));

  fs.writeFileSync(
    path.join(dir, 'main.dart.js'),
    'console.log("synthetic main");\n//# sourceMappingURL=main.dart.js.map\n',
  );
  fs.writeFileSync(
    path.join(dir, 'main.dart.js.map'),
    JSON.stringify({
      version: 3,
      sources: ['../../../lib/main.dart', '../../../lib/ui/pages/home_page.dart'],
      mappings: 'AAAA',
    }),
  );

  for (let i = 1; i <= DEFAULT_DEFERRED_MODULES.length; i++) {
    const part = `main.dart.js_${i}.part.js`;
    fs.writeFileSync(
      path.join(dir, part),
      `console.log("chunk ${i}");\n//# sourceMappingURL=${part}.map\n`,
    );
    fs.writeFileSync(
      path.join(dir, `${part}.map`),
      JSON.stringify({
        version: 3,
        sources: [`../../../lib/${DEFAULT_DEFERRED_MODULES[i - 1]}`],
        mappings: 'BBBB',
      }),
    );
  }

  fs.writeFileSync(
    path.join(dir, 'flutter_bootstrap.js'),
    '_flutter.buildConfig = {"engineRevision":"abc","builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"}]};\n_flutter.loader.load({});\n',
  );

  const fontDir = path.join(dir, 'assets', 'assets', 'fonts');
  fs.mkdirSync(fontDir, { recursive: true });
  const fontBuf = Buffer.alloc(25 * 1024, 0x5a);
  for (const f of DEFAULT_REQUIRED_FONTS) {
    fs.writeFileSync(path.join(fontDir, f), fontBuf);
  }
  return dir;
}

test('fingerprint_web_bundle.py hashes only main.dart.js + map, rewrites bootstrap, keeps .part.js untouched, is idempotent, and passes checkWebBundle', (t) => {
  const dir = createFixture(t);

  execFileSync('python3', [SCRIPT, dir], { stdio: 'pipe' });

  const entries = fs.readdirSync(dir);
  const mainFiles = entries.filter((f) => /^main\.[0-9a-f]{12}\.dart\.js$/.test(f));
  assert.equal(mainFiles.length, 1, `expected one hashed main.<12hex>.dart.js, got ${entries}`);
  const hashedMain = mainFiles[0];
  const hashedMap = `${hashedMain}.map`;

  assert.equal(fs.existsSync(path.join(dir, 'main.dart.js')), false, 'unhashed main.dart.js removed');
  assert.equal(fs.existsSync(path.join(dir, 'main.dart.js.map')), false, 'unhashed main.dart.js.map removed');
  assert.equal(fs.existsSync(path.join(dir, hashedMap)), true, 'hashed map exists');

  const mainContent = fs.readFileSync(path.join(dir, hashedMain), 'utf8');
  assert.ok(mainContent.includes(`//# sourceMappingURL=${hashedMap}`), 'sourceMappingURL updated');
  assert.equal(mainContent.includes('//# sourceMappingURL=main.dart.js.map'), false);

  const bootstrap = fs.readFileSync(path.join(dir, 'flutter_bootstrap.js'), 'utf8');
  assert.ok(bootstrap.includes(`"mainJsPath":"${hashedMain}"`), 'flutter_bootstrap.js updated');

  // Every .part.js and .part.js.map stays at its original filename.
  for (let i = 1; i <= DEFAULT_DEFERRED_MODULES.length; i++) {
    assert.equal(fs.existsSync(path.join(dir, `main.dart.js_${i}.part.js`)), true);
    assert.equal(fs.existsSync(path.join(dir, `main.dart.js_${i}.part.js.map`)), true);
  }

  // Idempotent on second run.
  execFileSync('python3', [SCRIPT, dir], { stdio: 'pipe' });
  const entriesAfterSecond = fs.readdirSync(dir);
  assert.deepEqual(entriesAfterSecond.sort(), entries.sort());

  // check_web_bundle accepts the fingerprinted bundle.
  const bundleCheck = checkWebBundle(dir, {
    maxGzipBytes: 50000,
    minPartCount: 6,
    minFontBytes: 20480,
  });
  assert.equal(bundleCheck.success, true, bundleCheck.errors.join('; '));
});

test('fingerprint_web_bundle.py cleans stale hashed files on an uncleaned rebuild directory', (t) => {
  const dir = createFixture(t);
  fs.writeFileSync(path.join(dir, 'main.deadbeef0000.dart.js'), 'stale');
  fs.writeFileSync(path.join(dir, 'main.deadbeef0000.dart.js.map'), '{}');

  execFileSync('python3', [SCRIPT, dir], { stdio: 'pipe' });

  assert.equal(fs.existsSync(path.join(dir, 'main.deadbeef0000.dart.js')), false);
  assert.equal(fs.existsSync(path.join(dir, 'main.deadbeef0000.dart.js.map')), false);
  const hashed = fs.readdirSync(dir).filter((f) => /^main\.[0-9a-f]{12}\.dart\.js$/.test(f));
  assert.equal(hashed.length, 1);
});

test('fingerprint_web_bundle.py exits non-zero and leaves main.dart.js intact on error conditions', (t) => {
  // 1. Missing directory.
  const missingDir = path.join(os.tmpdir(), `nonexistent-fp-${Date.now()}`);
  assert.throws(() => execFileSync('python3', [SCRIPT, missingDir], { stdio: 'pipe' }));

  // 2. Missing main.dart.js.
  const noMain = createFixture(t);
  fs.unlinkSync(path.join(noMain, 'main.dart.js'));
  assert.throws(() => execFileSync('python3', [SCRIPT, noMain], { stdio: 'pipe' }));

  // 3. Multiple ambiguous hashed main bundles.
  const multiMain = createFixture(t);
  fs.unlinkSync(path.join(multiMain, 'main.dart.js'));
  fs.writeFileSync(path.join(multiMain, 'main.0123456789ab.dart.js'), 'a');
  fs.writeFileSync(path.join(multiMain, 'main.fedcba987654.dart.js'), 'b');
  assert.throws(() => execFileSync('python3', [SCRIPT, multiMain], { stdio: 'pipe' }));

  // 4. Missing flutter_bootstrap.js leaves main.dart.js and .map untouched (atomic failure).
  const noBootstrap = createFixture(t);
  fs.unlinkSync(path.join(noBootstrap, 'flutter_bootstrap.js'));
  assert.throws(() => execFileSync('python3', [SCRIPT, noBootstrap], { stdio: 'pipe' }));
  assert.equal(fs.existsSync(path.join(noBootstrap, 'main.dart.js')), true);
  assert.equal(fs.existsSync(path.join(noBootstrap, 'main.dart.js.map')), true);

  // 5. Malformed flutter_bootstrap.js leaves main.dart.js untouched.
  const badBootstrap = createFixture(t);
  fs.writeFileSync(path.join(badBootstrap, 'flutter_bootstrap.js'), 'console.log("no buildConfig");');
  assert.throws(() => execFileSync('python3', [SCRIPT, badBootstrap], { stdio: 'pipe' }));
  assert.equal(fs.existsSync(path.join(badBootstrap, 'main.dart.js')), true);
});
