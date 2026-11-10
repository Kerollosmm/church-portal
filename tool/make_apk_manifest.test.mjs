import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { resolveDownloadUrl, detectApkAbi, buildManifest } from './make_apk_manifest.mjs';

test('resolveDownloadUrl rewrites GitHub releases-repo URLs to tag path', () => {
  const base = 'https://github.com/Kerollosmm/church-portal-apk/releases/latest/download/';
  const tag = 'apk-v1.2.0';
  const url = resolveDownloadUrl(base, tag, 'church-portal-arm64.apk');
  assert.equal(
    url,
    'https://github.com/Kerollosmm/church-portal-apk/releases/download/apk-v1.2.0/church-portal-arm64.apk'
  );
});

test('resolveDownloadUrl rewrites GitHub this-repo URLs to tag path', () => {
  const base = 'https://github.com/Kerollosmm/church-portal/releases/latest/download/';
  const tag = 'apk-v1.2.0';
  const url = resolveDownloadUrl(base, tag, 'church-portal-arm32.apk');
  assert.equal(
    url,
    'https://github.com/Kerollosmm/church-portal/releases/download/apk-v1.2.0/church-portal-arm32.apk'
  );
});

test('resolveDownloadUrl leaves Firebase base URL completely untouched', () => {
  const base = 'https://maximos-domadios-church.web.app/app/android/';
  const url = resolveDownloadUrl(base, 'apk-v1.2.0', 'church-portal-arm64.apk');
  assert.equal(url, 'https://maximos-domadios-church.web.app/app/android/church-portal-arm64.apk');
});

test('resolveDownloadUrl fails if tag is omitted when using GitHub base URL', () => {
  const base = 'https://github.com/Kerollosmm/church-portal-apk/releases/latest/download/';
  assert.throws(
    () => resolveDownloadUrl(base, '', 'church-portal-arm64.apk'),
    /--tag is required when using a GitHub releases base URL/
  );
});

test('detectApkAbi identifies arm64 and arm32 accurately', () => {
  assert.equal(detectApkAbi('church-portal-arm64.apk'), 'arm64-v8a');
  assert.equal(detectApkAbi('app-arm64-v8a-release.apk'), 'arm64-v8a');
  assert.equal(detectApkAbi('church-portal-arm32.apk'), 'armeabi-v7a');
  assert.equal(detectApkAbi('app-armeabi-v7a-release.apk'), 'armeabi-v7a');
});

test('buildManifest generates complete manifest with SHA-256 and size', () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'apk-test-'));
  const apk64 = path.join(tmpDir, 'church-portal-arm64.apk');
  const apk32 = path.join(tmpDir, 'church-portal-arm32.apk');
  fs.writeFileSync(apk64, 'dummy arm64 bytes');
  fs.writeFileSync(apk32, 'dummy arm32 bytes');

  const manifest = buildManifest({
    version: '1.2.0',
    build: 5,
    minSupportedBuild: 1,
    notesAr: 'ملاحظات الإصدار',
    baseUrl: 'https://github.com/Kerollosmm/church-portal-apk/releases/latest/download/',
    tag: 'apk-v1.2.0',
    apkFiles: [apk64, apk32],
  });

  assert.equal(manifest.schema, 1);
  assert.equal(manifest.version, '1.2.0');
  assert.equal(manifest.build, 5);
  assert.equal(manifest.notesAr, 'ملاحظات الإصدار');
  assert.ok(manifest.apks['arm64-v8a']);
  assert.ok(manifest.apks['armeabi-v7a']);
  assert.equal(manifest.apks['arm64-v8a'].size, 17);
  assert.ok(manifest.apks['arm64-v8a'].sha256.length === 64);
  assert.ok(manifest.apks['arm64-v8a'].url.includes('/releases/download/apk-v1.2.0/church-portal-arm64.apk'));

  fs.rmSync(tmpDir, { recursive: true, force: true });
});

test('readPubspecVersion reads the repo pubspec independently of the working directory', async () => {
  const { readPubspecVersion, defaultPubspecPath } = await import('./make_apk_manifest.mjs');
  const cwd = process.cwd();
  process.chdir(os.tmpdir());
  try {
    const pv = readPubspecVersion(defaultPubspecPath);
    assert.ok(pv, 'pubspec found from another cwd');
    assert.match(pv.version, /^[0-9]+\.[0-9]+\.[0-9]+$/);
    assert.ok(Number.isInteger(pv.build) && pv.build >= 1);
  } finally {
    process.chdir(cwd);
  }
});

test('readPubspecVersion returns null for a missing file', async () => {
  const { readPubspecVersion } = await import('./make_apk_manifest.mjs');
  assert.equal(readPubspecVersion(path.join(os.tmpdir(), 'no-such-pubspec.yaml')), null);
});
